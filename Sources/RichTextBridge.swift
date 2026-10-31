import AppKit

@MainActor final class EditorBridge {
    var noteID=""
    var loadVersion:UInt?
    var capture:(()->NoteDocument)?
    func document(noteID:String,fallback:String)->NoteDocument {self.noteID==noteID ? (capture?() ?? NoteDocument(text:fallback)) : NoteDocument(text:fallback)}
}

@MainActor enum RichTextBridge {
    static func attributes(settings:EditorSettings,lists:[NSTextList]=[])->[NSAttributedString.Key:Any] {
        let p=settings.paragraph.mutableCopy() as! NSMutableParagraphStyle
        p.textLists=lists
        if !lists.isEmpty {p.headIndent=CGFloat(lists.count)*28; p.firstLineHeadIndent=p.headIndent-20}
        return [.font:settings.font,.foregroundColor:NSColor.textColor,.paragraphStyle:p,.kern:settings.characterSpacing]
    }
    static func attributed(_ document:NoteDocument,settings:EditorSettings)->(NSAttributedString,[NSAttributedString.Key:Any]) {
        var objects:[Int:NSTextList]=[:]
        let result=NSMutableAttributedString(string:"")
        var last=attributes(settings:settings)
        for (i,p) in document.paragraphs.enumerated() {
            let lists=p.lists.map {list -> NSTextList in
                if let old=objects[list.id] {return old}
                let format:NSTextList.MarkerFormat=list.ordered ? NSTextList.MarkerFormat(rawValue:"{decimal}.") : (list.kind=="dash" ? .hyphen : (list.kind=="circle" ? .circle : .disc))
                let object=NSTextList(markerFormat:format,options:[],startingItemNumber:list.start)
                objects[list.id]=object; return object
            }
            last=attributes(settings:settings,lists:lists)
            result.append(NSAttributedString(string:p.text+(i<document.paragraphs.count-1 || !p.lists.isEmpty ? "\n" : ""),attributes:last))
        }
        return (result,last)
    }
    static func capture(_ view:NSTextView)->NoteDocument {
        guard let storage=view.textStorage else {return NoteDocument(text:view.string)}
        let ns=storage.string as NSString
        var ids:[ObjectIdentifier:Int]=[:]; var result:[NoteParagraph]=[]; var location=0
        func styles(_ attrs:[NSAttributedString.Key:Any])->[NoteList] {
            ((attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []).map {list in
                let identity=ObjectIdentifier(list)
                if ids[identity]==nil {ids[identity]=ids.count+1}
                return NoteList(id:ids[identity]!,kind:list.isOrdered ? "decimal" : (list.markerFormat == .hyphen ? "dash" : (list.markerFormat == .circle ? "circle" : "disc")),start:list.startingItemNumber)
            }
        }
        while location<ns.length {
            var start=0; var end=0; var contentsEnd=0
            ns.getParagraphStart(&start,end:&end,contentsEnd:&contentsEnd,for:NSRange(location:location,length:0))
            guard end>location else {break}
            result.append(NoteParagraph(text:ns.substring(with:NSRange(location:start,length:contentsEnd-start)),lists:styles(storage.attributes(at:start,effectiveRange:nil))))
            location=end
        }
        if ns.length==0 || ns.hasSuffix("\n") {result.append(NoteParagraph(text:""))}
        return NoteDocument(paragraphs:result)
    }
}
