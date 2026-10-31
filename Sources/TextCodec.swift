import Foundation

struct EditingProfile:Sendable {
    var reason: String?
    var titleTemplate: String?
    var editable: Bool { reason == nil }
}

enum NoteCodec {
    static let titleToken = "__NOTESPLUS_TITLE_TEXT_7E0901__"
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    static func normalized(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{00a0}", with: " ")
        while value.hasSuffix("\n") { value.removeLast() }
        return value
    }
    static func html(for text: String, profile: EditingProfile = EditingProfile()) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return lines.enumerated().map { index, line in
            if index == 0, let template = profile.titleTemplate {
                return template.replacingOccurrences(of: titleToken, with: lineHTML(line))
            }
            return "<div>\(line.isEmpty ? "<br>" : lineHTML(line))</div>"
        }.joined(separator: "\n")
    }
    static func lineHTML(_ line:String)->String {
        let characters=Array(line)
        return characters.enumerated().map { index, character in
            if character == "\t" { return "<span class=\"Apple-tab-span\" style=\"white-space:pre\">\t</span>" }
            if character == " ", index==0 || index==characters.count-1 || (index>0 && characters[index-1]==" ") || (index+1<characters.count && characters[index+1]==" ") { return "&nbsp;" }
            if character == "\u{2028}" {return "<br>"}
            return escape(String(character))
        }.joined()
    }
    static func profile(html: String, plaintext: String, locked: Bool, shared: Bool, attachments: Int) -> EditingProfile {
        if locked { return EditingProfile(reason: "잠긴 메모 · 기본 메모에서 열기") }
        if shared { return EditingProfile(reason: "공유 메모 · 기본 메모에서 편집") }
        if attachments > 0 { return EditingProfile(reason: "첨부파일 \(attachments)개 · 기본 메모에서 편집") }
        guard !html.isEmpty else { return EditingProfile() }
        // Tidy parses the HTML as data. External entities are explicitly disabled.
        guard let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let body = try? document.nodes(forXPath: "//body").first else {
            return EditingProfile(reason: "서식을 확인할 수 없습니다 · 기본 메모에서 편집")
        }
        // Notes exports an unchecked checklist as the same <ul><li> HTML as a bullet list.
        // The public bridge cannot preserve that hidden check state, so never rewrite UL notes.
        if let unordered=try? document.nodes(forXPath:"//ul"),!unordered.isEmpty {
            return EditingProfile(reason:"글머리·체크리스트 · 체크 상태 보존을 위해 기본 메모에서 편집")
        }
        let nodes = (body.children ?? []).filter { $0.kind != .comment && !($0.kind == .text && ($0.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        var template: String?
        for (index, node) in nodes.enumerated() {
            if isPlain(node) || isList(node) { continue }
            if index==0, let element=node as? XMLElement, isSimpleTitle(element),
               normalized(element.stringValue ?? "").isEmpty,
               normalized(plaintext.components(separatedBy:"\n").first ?? "").isEmpty,
               let copy=element.copy() as? XMLElement,
               let leaves=try? copy.nodes(forXPath:"descendant-or-self::*[not(*)]"), leaves.count==1,
               let leaf=leaves.first as? XMLElement,
               let target=(leaf.name?.lowercased()=="br" ? leaf.parent : leaf) as? XMLElement {
                target.setChildren([XMLNode.text(withStringValue:titleToken) as! XMLNode])
                template=copy.xmlString; continue
            }
            if index == 0, let element = node as? XMLElement,
               isSimpleTitle(element),
               normalized(element.stringValue ?? "") == normalized(plaintext.components(separatedBy: "\n").first ?? ""),
               let copy = element.copy() as? XMLElement,
               let leaves = try? copy.nodes(forXPath: ".//text()"),
               leaves.filter({ !($0.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count == 1,
               let leaf = leaves.first(where: { !($0.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                leaf.stringValue = titleToken
                template = copy.xmlString
                continue
            }
            return EditingProfile(reason: "복잡한 서식 · 기본 메모에서 편집")
        }
        return EditingProfile(titleTemplate: template)
    }
    static func html(for document:NoteDocument,profile:EditingProfile=EditingProfile())->String {
        var output=""; var open:[NoteList]=[]
        func close(to count:Int) {
            while open.count>count {let list=open.removeLast(); output += "</li></\(list.ordered ? "ol" : "ul")>\n"}
        }
        for (index,p) in document.paragraphs.enumerated() {
            if p.lists.isEmpty {
                close(to:0)
                if index==0, let title=profile.titleTemplate {output += title.replacingOccurrences(of:titleToken,with:lineHTML(p.text))+"\n"}
                else {output += "<div>\(p.text.isEmpty ? "<br>" : lineHTML(p.text))</div>\n"}
                continue
            }
            var common=0
            while common<min(open.count,p.lists.count),open[common]==p.lists[common] {common += 1}
            close(to:common)
            if common==p.lists.count {output += "</li>\n"}
            for depth in common..<p.lists.count {
                let list=p.lists[depth]
                if list.ordered {output += list.start==1 ? "<ol>\n" : "<ol start=\"\(list.start)\">\n"}
                else if list.kind=="dash" {output += "<ul class=\"Apple-dash-list\">\n"}
                else {output += "<ul>\n"}
                open.append(list)
                if depth<p.lists.count-1 {output += "<li>"}
            }
            output += "<li>\(p.text.isEmpty ? "<br>" : lineHTML(p.text))"
        }
        close(to:0); return output
    }
    static func document(html:String,plaintext:String,profile:EditingProfile)->NoteDocument? {
        guard profile.editable else {return nil}
        guard !html.isEmpty else {return NoteDocument(text:plaintext)}
        guard let dom=try? XMLDocument(xmlString:html,options:[.documentTidyHTML,.nodeLoadExternalEntitiesNever]),
              let body=(try? dom.nodes(forXPath:"//body"))?.first else {return nil}
        var paragraphs:[NoteParagraph]=[]; var nextID=0
        func meaningful(_ node:XMLNode)->Bool {node.kind != .comment && !(node.kind == .text && (node.stringValue ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
        func inline(_ node:XMLNode)->String {
            if node.kind == .text {return (node.stringValue ?? "").replacingOccurrences(of:"\u{00a0}",with:" ")}
            if node.name?.lowercased()=="br" {return "\u{2028}"}
            if ["ol","ul"].contains(node.name?.lowercased() ?? "") {return ""}
            return (node.children ?? []).map(inline).joined()
        }
        func content(_ nodes:[XMLNode])->String {
            var t=nodes.map(inline).joined()
            // The final BR in Notes HTML terminates a paragraph; interior BRs are soft breaks.
            while t.hasSuffix("\n") {t.removeLast()}
            if t.hasSuffix("\u{2028}") {t.removeLast()}
            return t
        }
        func parseList(_ node:XMLElement,_ parents:[NoteList]) {
            nextID += 1
            let kind=node.name=="ol" ? "decimal" : (node.attribute(forName:"class")?.stringValue=="Apple-dash-list" ? "dash" : "disc")
            let list=NoteList(id:nextID,kind:kind,start:Int(node.attribute(forName:"start")?.stringValue ?? "1") ?? 1)
            let stack=parents+[list]
            for item in (node.children ?? []).compactMap({$0 as? XMLElement}) where item.name=="li" {
                let children=item.children ?? []
                let nested=children.compactMap{$0 as? XMLElement}.filter{["ol","ul"].contains($0.name ?? "")}
                paragraphs.append(NoteParagraph(text:content(children.filter{!["ol","ul"].contains($0.name ?? "")}),lists:stack))
                for child in nested {parseList(child,stack)}
            }
        }
        for node in (body.children ?? []).filter(meaningful) {
            if let list=node as? XMLElement,["ol","ul"].contains(list.name ?? "") {parseList(list,[])}
            else {paragraphs.append(NoteParagraph(text:content([node])))}
        }
        let result=NoteDocument(paragraphs:paragraphs)
        // This also catches block shapes our restricted parser cannot faithfully represent.
        guard normalized(result.text.replacingOccurrences(of:"\u{2028}",with:"\n"))==normalized(plaintext) else {return nil}
        return result
    }
    private static func isList(_ node:XMLNode)->Bool {
        guard let e=node as? XMLElement,["ol","ul"].contains(e.name ?? "") else {return false}
        for a in e.attributes ?? [] {
            if a.name=="start",e.name=="ol",let n=Int(a.stringValue ?? ""),n>0,n<1_000_000_000 {continue}
            if a.name=="class",e.name=="ul",a.stringValue=="Apple-dash-list" {continue}
            return false
        }
        let children=(e.children ?? []).filter{!($0.kind == .text && ($0.stringValue ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
        return !children.isEmpty && children.allSatisfy {node in
            guard let li=node as? XMLElement,li.name=="li",(li.attributes ?? []).isEmpty else {return false}
            // Nested lists must follow item text; otherwise saving would reorder content.
            var foundNested=false
            for child in li.children ?? [] {
                if isList(child) {foundNested=true; continue}
                if foundNested {
                    if child.kind == .text && (child.stringValue ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {continue}
                    return false
                }
                if !isPlain(child) {return false}
            }
            return true
        }
    }
    private static func isPlain(_ node: XMLNode) -> Bool {
        if node.kind == .text || node.kind == .comment { return true }
        guard let element = node as? XMLElement, ["div", "p", "br", "span", "font"].contains(element.name?.lowercased() ?? "") else { return false }
        // Preserve meaningful formatting by refusing to flatten it on save.
        if !(element.attributes ?? []).isEmpty {
            // Notes inserts these fallback faces for Korean while canonicalizing lists.
            if element.name=="font", element.attributes?.count==1,
               element.attribute(forName:"face")?.stringValue?.hasPrefix(".Apple")==true {
                return (element.children ?? []).allSatisfy(isPlain)
            }
            return element.name == "span" && element.attribute(forName:"class")?.stringValue == "Apple-tab-span"
                && Set((element.attributes ?? []).compactMap(\.name)).isSubset(of:["class","style"])
                && (element.stringValue ?? "").trimmingCharacters(in:.whitespaces).isEmpty
        }
        return (element.children ?? []).allSatisfy(isPlain)
    }
    private static func isSimpleTitle(_ node: XMLNode) -> Bool {
        if node.kind == .text { return true }
        guard let element = node as? XMLElement,
              ["div", "p", "h1", "h2", "h3", "b", "strong", "span", "font", "br"].contains(element.name?.lowercased() ?? "") else { return false }
        let attributes = element.attributes ?? []
        if attributes.contains(where: { !["style", "face", "size", "color"].contains($0.name ?? "") }) { return false }
        return (element.children ?? []).allSatisfy(isSimpleTitle)
    }
}
