import AppKit
import SwiftUI

extension NSAttributedString.Key {
    static let npKind=Self("NotesPlus.kind"),npDone=Self("NotesPlus.done"),npIndent=Self("NotesPlus.indent"),npNumber=Self("NotesPlus.number"),npQuote=Self("NotesPlus.quote"),npTable=Self("NotesPlus.table"),npRow=Self("NotesPlus.row"),npColumn=Self("NotesPlus.column")
    static let npInlineBold=Self("NotesPlus.inlineBold")
}
final class ListMarkerCell:NSTextAttachmentCell {
    var kind:String;var done:Bool;var number:Int
    init(kind:String,done:Bool=false,number:Int=1) {self.kind=kind;self.done=done;self.number=number;super.init(textCell:"")}
    required init(coder:NSCoder) {kind="bulletList";done=false;number=1;super.init(coder:coder)}
    override func cellSize()->NSSize {NSSize(width:22,height:20)}
    override func cellBaselineOffset()->NSPoint {NSPoint(x:0,y:-4)}
    override func draw(withFrame rect:NSRect,in controlView:NSView?) {
        let center=NSPoint(x:rect.midX,y:rect.midY)
        if kind=="todoList" {
            let circle=NSBezierPath(ovalIn:NSRect(x:center.x-7,y:center.y-7,width:14,height:14));circle.lineWidth=1.4
            (done ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setStroke();circle.stroke()
            if done {NSColor.controlAccentColor.setFill();circle.fill();NSColor.white.setStroke();let path=NSBezierPath();path.lineWidth=1.7;path.move(to:NSPoint(x:center.x-4,y:center.y));path.line(to:NSPoint(x:center.x-1,y:center.y+3));path.line(to:NSPoint(x:center.x+4,y:center.y-3));path.stroke()}
        } else {
            let label=kind=="numberedList" ? "\(number)." : (kind=="dashList" ? "–" : "•")
            (label as NSString).draw(at:NSPoint(x:rect.minX+3,y:rect.minY),withAttributes:[.font:NSFont.systemFont(ofSize:15),.foregroundColor:NSColor.labelColor])
        }
    }
}
@MainActor final class StructuredEditorHandle:ObservableObject {
    weak var view:StructuredTextView?
    func format(_ kind:String) {view?.setParagraphKind(kind)}
    func inline(_ key:String) {view?.toggleInline(key)}
    func capture()->CloudDocument? {view.map{StructuredCodec.capture($0)}}
}

enum StructuredCodec {
    static func attributes(_ p:CloudParagraph,size:Double,ratio:Double)->[NSAttributedString.Key:Any] {
        let style=NSMutableParagraphStyle();style.paragraphSpacing=4
        let isList=p.kind.hasSuffix("List")
        style.firstLineHeadIndent=CGFloat(p.indent*24);style.headIndent=CGFloat(p.indent*24+(isList ? 30:0));style.tabStops=[NSTextTab(textAlignment:.left,location:style.headIndent,options:[:])]
        let fontSize=size+(p.kind=="title" ? 7 : p.kind=="heading" ? 4 : p.kind=="subheading" ? 2:0)
        style.minimumLineHeight=fontSize*ratio;style.maximumLineHeight=fontSize*ratio
        let font=p.kind=="monospaced" ? NSFont.monospacedSystemFont(ofSize:fontSize,weight:.regular) : NSFont.systemFont(ofSize:fontSize,weight:["title","heading","subheading"].contains(p.kind) ? .semibold:.regular)
        return [.font:font,.foregroundColor:NSColor.labelColor,.paragraphStyle:style,.npKind:p.kind,.npDone:p.done ?? false,.npIndent:p.indent,.npNumber:p.startNumber,.npQuote:p.blockQuoteLevel,.npInlineBold:false]
    }
    static func prefix(kind:String,done:Bool,number:Int,attributes:[NSAttributedString.Key:Any])->NSAttributedString {
        let attachment=NSTextAttachment();attachment.attachmentCell=ListMarkerCell(kind:kind,done:done,number:number)
        let out=NSMutableAttributedString(attachment:attachment);out.addAttributes(attributes,range:NSRange(location:0,length:1));out.append(NSAttributedString(string:"\t",attributes:attributes));return out
    }
    static func attributed(_ document:CloudDocument,size:Double,ratio:Double)->NSAttributedString {
        let out=NSMutableAttributedString(string:"");var number=0
        for (index,p) in document.paragraphs.enumerated() {
            if let id=p.tableID,let table=document.tables.first(where:{$0.id==id}) {
                let textTable=NSTextTable();textTable.numberOfColumns=table.grid.first?.count ?? 1;textTable.collapsesBorders=true;textTable.layoutAlgorithm = .automaticLayoutAlgorithm
                for (row,cells) in table.grid.enumerated() {for (column,text) in cells.enumerated() {
                    let block=NSTextTableBlock(table:textTable,startingRow:row,rowSpan:1,startingColumn:column,columnSpan:1)
                    block.setWidth(1,type:.absoluteValueType,for:.border);block.setBorderColor(.separatorColor);block.setWidth(7,type:.absoluteValueType,for:.padding)
                    block.setValue(100/CGFloat(max(1,cells.count)),type:.percentageValueType,for:.width)
                    var attrs=attributes(CloudParagraph(),size:size,ratio:ratio)
                    let style=(attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle;style.textBlocks=[block];attrs[.paragraphStyle]=style
                    attrs[.npTable]=id;attrs[.npRow]=row;attrs[.npColumn]=column
                    out.append(NSAttributedString(string:text+"\n",attributes:attrs))
                }}
                number=0;continue
            }
            let attrs=attributes(p,size:size,ratio:ratio)
            if p.kind=="numberedList" {number=p.startNumber>0 ? p.startNumber : number+1}else{number=0}
            if p.kind.hasSuffix("List") {out.append(prefix(kind:p.kind,done:p.done ?? false,number:max(1,number),attributes:attrs))}
            let body=NSMutableAttributedString(string:p.text,attributes:attrs);var at=0
            for span in p.spans {
                guard at+span.length<=body.length else{break}
                var extras:[NSAttributedString.Key:Any]=[:];var font=attrs[.font] as! NSFont
                if span.bold {font=NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask)}
                if span.italic {font=NSFontManager.shared.convert(font,toHaveTrait:.italicFontMask)}
                extras[.font]=font
                extras[.npInlineBold]=span.bold
                if span.underline {extras[.underlineStyle]=NSUnderlineStyle.single.rawValue}
                if span.strikethrough {extras[.strikethroughStyle]=NSUnderlineStyle.single.rawValue}
                if !span.link.isEmpty {extras[.link]=span.link}
                body.addAttributes(extras,range:NSRange(location:at,length:span.length));at+=span.length
            }
            out.append(body)
            if index<document.paragraphs.count-1 {out.append(NSAttributedString(string:p.separator?.isEmpty==false ? p.separator! : "\n",attributes:attrs))}
        }
        return out
    }
    static func capture(_ view:NSTextView)->CloudDocument {
        let storage=view.attributedString(),string=storage.string as NSString
        var paragraphs:[CloudParagraph]=[],tables:[CloudTable]=[],at=0,tableIndex:[String:Int]=[:]
        while at<storage.length {
            let range=string.paragraphRange(for:NSRange(location:at,length:0));let full=string.substring(with:range)
            let separator=full.hasSuffix("\r\n") ? "\r\n" : (full.hasSuffix("\n") ? "\n" : full.hasSuffix("\r") ? "\r" : "")
            let attrs=storage.attributes(at:at,effectiveRange:nil)
            let contentLength=range.length-(separator as NSString).length
            if let id=attrs[.npTable] as? String {
                let row=attrs[.npRow] as? Int ?? 0,col=attrs[.npColumn] as? Int ?? 0
                if tableIndex[id]==nil {
                    tableIndex[id]=tables.count;tables.append(CloudTable(id:id,grid:[]))
                    var p=CloudParagraph(text:"\u{fffc}");p.tableID=id;p.separator="\n";paragraphs.append(p)
                }
                let ti=tableIndex[id]!
                while tables[ti].grid.count<=row {tables[ti].grid.append([])}
                while tables[ti].grid[row].count<=col {tables[ti].grid[row].append("")}
                let text=string.substring(with:NSRange(location:at,length:contentLength))
                tables[ti].grid[row][col]+=text
                // Multiple paragraphs belonging to the same cell retain their internal newline.
                if NSMaxRange(range)<storage.length,storage.attribute(.npTable,at:NSMaxRange(range),effectiveRange:nil) as? String==id,
                   storage.attribute(.npRow,at:NSMaxRange(range),effectiveRange:nil) as? Int==row,
                   storage.attribute(.npColumn,at:NSMaxRange(range),effectiveRange:nil) as? Int==col {tables[ti].grid[row][col]+=separator}
            } else {
                let kind=attrs[.npKind] as? String ?? "body"
                let prefix=kind.hasSuffix("List") && storage.attribute(.attachment,at:at,effectiveRange:nil) is NSTextAttachment ? min(2,contentLength):0
                let content=NSRange(location:at+prefix,length:contentLength-prefix)
                var p=CloudParagraph(text:string.substring(with:content),kind:kind)
                p.indent=attrs[.npIndent] as? Int ?? 0;p.blockQuoteLevel=attrs[.npQuote] as? Int ?? 0;p.startNumber=attrs[.npNumber] as? Int ?? 0;p.separator=separator
                p.done=kind=="todoList" ? (attrs[.npDone] as? Bool ?? false):nil;p.spans=[]
                storage.enumerateAttributes(in:content) {a,r,_ in
                    let traits=(a[.font] as? NSFont).map{NSFontManager.shared.traits(of:$0)} ?? []
                    let span=CloudSpan(length:r.length,bold:a[.npInlineBold] as? Bool ?? traits.contains(.boldFontMask),italic:traits.contains(.italicFontMask),underline:(a[.underlineStyle] as? Int ?? 0)>0,strikethrough:(a[.strikethroughStyle] as? Int ?? 0)>0,link:(a[.link] as? URL)?.absoluteString ?? a[.link] as? String ?? "")
                    if var last=p.spans.last,CloudSpan(length:span.length,bold:last.bold,italic:last.italic,underline:last.underline,strikethrough:last.strikethrough,link:last.link)==span {last.length+=span.length;p.spans[p.spans.count-1]=last}else{p.spans.append(span)}
                }
                paragraphs.append(p)
            }
            at=NSMaxRange(range)
        }
        if paragraphs.isEmpty || string.hasSuffix("\n") || string.hasSuffix("\r") {paragraphs.append(CloudParagraph())}
        return CloudDocument(paragraphs:paragraphs,tables:tables)
    }
}

final class StructuredTextView:NSTextView {
    var size=17.0,ratio=1.6
    var onChange:(()->Void)?
    private var converting=false
    override func paste(_ sender:Any?) {super.pasteAsPlainText(sender)}
    func paragraphRange()->NSRange {(string as NSString).paragraphRange(for:NSRange(location:min(selectedRange().location,(string as NSString).length),length:0))}
    func attrsAtCaret()->[NSAttributedString.Key:Any] {let at=selectedRange().location;return at<(textStorage?.length ?? 0) ? textStorage!.attributes(at:at,effectiveRange:nil):typingAttributes}
    override func insertText(_ insertString:Any,replacementRange:NSRange) {
        super.insertText(insertString,replacementRange:replacementRange)
        guard !converting,!hasMarkedText(),(insertString as? String)==" ",attrsAtCaret()[.npTable]==nil else{return}
        let range=paragraphRange(),line=(string as NSString).substring(with:range).trimmingCharacters(in:.newlines)
        guard line.range(of:"^[0-9]{1,6}\\. $",options:.regularExpression) != nil,let n=Int(line.dropLast(2)),n>0 else{return}
        converting=true;defer{converting=false}
        var p=CloudParagraph(kind:"numberedList");p.startNumber=n
        let attrs=StructuredCodec.attributes(p,size:size,ratio:ratio)
        super.insertText(StructuredCodec.prefix(kind:p.kind,done:false,number:n,attributes:attrs),replacementRange:NSRange(location:range.location,length:(line as NSString).length));typingAttributes=attrs
    }
    override func deleteBackward(_ sender:Any?) {
        let range=paragraphRange()
        if !hasMarkedText(),selectedRange().length==0,selectedRange().location==range.location+2,attrsAtCaret()[.npTable]==nil,(attrsAtCaret()[.npKind] as? String ?? "").hasSuffix("List") {setParagraphKind("body");setSelectedRange(NSRange(location:range.location,length:0));return}
        super.deleteBackward(sender)
    }
    override func insertTab(_ sender:Any?) {
        let attrs=attrsAtCaret()
        if let id=attrs[.npTable] as? String,let storage=textStorage {
            let row=attrs[.npRow] as? Int,col=attrs[.npColumn] as? Int
            var at=NSMaxRange(paragraphRange())
            while at<storage.length {
                let a=storage.attributes(at:at,effectiveRange:nil)
                if a[.npTable] as? String != id || a[.npRow] as? Int != row || a[.npColumn] as? Int != col {setSelectedRange(NSRange(location:at,length:0));return}
                at=NSMaxRange((string as NSString).paragraphRange(for:NSRange(location:at,length:0)))
            }
            setSelectedRange(NSRange(location:storage.length,length:0));return
        }
        super.insertTab(sender)
    }
    func refreshNumbers() {
        guard let storage=textStorage else{return};var number=0,at=0
        while at<storage.length {
            let range=(string as NSString).paragraphRange(for:NSRange(location:at,length:0)),attrs=storage.attributes(at:at,effectiveRange:nil)
            if attrs[.npKind] as? String=="numberedList" {
                let start=attrs[.npNumber] as? Int ?? 0;number=start>0 ? start:number+1
                if let attachment=attrs[.attachment] as? NSTextAttachment,let cell=attachment.attachmentCell as? ListMarkerCell,cell.number != number {cell.number=number;layoutManager?.invalidateDisplay(forCharacterRange:NSRange(location:at,length:1))}
            }else{number=0}
            at=NSMaxRange(range)
        }
    }
    func setParagraphKind(_ kind:String) {
        guard !hasMarkedText() else{return}
        let selection=selectedRange(),range=(string as NSString).paragraphRange(for:selection)
        var containsTable=false
        textStorage?.enumerateAttribute(.npTable,in:range){value,_,_ in if value != nil {containsTable=true}}
        guard !containsTable else{return}
        let slice=NSTextView();slice.textStorage?.setAttributedString(attributedSubstring(forProposedRange:range,actualRange:nil) ?? NSAttributedString(string:""))
        var document=StructuredCodec.capture(slice)
        if document.paragraphs.last?.text.isEmpty==true,document.paragraphs.count>1 {document.paragraphs.removeLast()}
        for i in document.paragraphs.indices where document.paragraphs[i].tableID==nil {document.paragraphs[i].kind=kind;document.paragraphs[i].done=kind=="todoList" ? false:nil;document.paragraphs[i].startNumber=0}
        let replacement=NSMutableAttributedString(attributedString:StructuredCodec.attributed(document,size:size,ratio:ratio))
        if range.length>0,(string as NSString).substring(with:range).hasSuffix("\n") {replacement.append(NSAttributedString(string:"\n",attributes:StructuredCodec.attributes(document.paragraphs.last ?? CloudParagraph(),size:size,ratio:ratio)))}
        if replacement.length==0 && kind.hasSuffix("List") {replacement.append(StructuredCodec.prefix(kind:kind,done:false,number:1,attributes:StructuredCodec.attributes(CloudParagraph(kind:kind),size:size,ratio:ratio)))}
        insertText(replacement,replacementRange:range);window?.makeFirstResponder(self)
        undoManager?.setActionName("문단 서식")
    }
    func toggleInline(_ key:String) {
        guard !hasMarkedText() else{return}
        let range=selectedRange();var attrs=attrsAtCaret()
        if key=="bold" || key=="italic" {
            let font=attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize:size),trait:NSFontTraitMask=key=="bold" ? .boldFontMask:.italicFontMask
            let enabled=key=="bold" ? (attrs[.npInlineBold] as? Bool ?? false):NSFontManager.shared.traits(of:font).contains(trait)
            attrs[.font]=enabled ? NSFontManager.shared.convert(font,toNotHaveTrait:trait):NSFontManager.shared.convert(font,toHaveTrait:trait)
            if key=="bold" {attrs[.npInlineBold] = !enabled}
        }else{attrs[.underlineStyle]=(attrs[.underlineStyle] as? Int ?? 0)>0 ? 0:1}
        if range.length==0 {typingAttributes=attrs}else{
            let content=NSMutableAttributedString(attributedString:attributedString().attributedSubstring(from:range));let attr:NSAttributedString.Key=key=="underline" ? .underlineStyle:.font
            content.addAttribute(attr,value:attrs[attr]!,range:NSRange(location:0,length:content.length))
            if key=="bold" {content.addAttribute(.npInlineBold,value:attrs[.npInlineBold]!,range:NSRange(location:0,length:content.length))}
            insertText(content,replacementRange:range);setSelectedRange(range)
        }
        window?.makeFirstResponder(self)
    }
    override func insertNewline(_ sender:Any?) {
        guard !hasMarkedText() else{super.insertNewline(sender);return}
        let attrs=attrsAtCaret(),kind=attrs[.npKind] as? String ?? "body"
        if attrs[.npTable] != nil {super.insertNewline(sender);return}
        if kind.hasSuffix("List") {
            let range=paragraphRange(),line=(string as NSString).substring(with:range).trimmingCharacters(in:.newlines)
            if line=="\u{fffc}\t" {setParagraphKind("body");return}
            var p=CloudParagraph(kind:kind);p.indent=attrs[.npIndent] as? Int ?? 0;p.done=false
            let next=StructuredCodec.attributes(p,size:size,ratio:ratio)
            let content=NSMutableAttributedString(string:"\n",attributes:attrs)
            content.append(StructuredCodec.prefix(kind:kind,done:false,number:1,attributes:next));insertText(content,replacementRange:selectedRange());typingAttributes=next
        }else {super.insertNewline(sender);typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:size,ratio:ratio)}
    }
    override func mouseDown(with event:NSEvent) {
        if let lm=layoutManager,let tc=textContainer,let storage=textStorage {
            var point=convert(event.locationInWindow,from:nil);point.x-=textContainerOrigin.x;point.y-=textContainerOrigin.y
            let glyph=lm.glyphIndex(for:point,in:tc)
            if glyph<lm.numberOfGlyphs {
                let index=lm.characterIndexForGlyph(at:glyph)
                if index<storage.length,storage.attribute(.attachment,at:index,effectiveRange:nil) is NSTextAttachment,
                   storage.attribute(.npKind,at:index,effectiveRange:nil) as? String=="todoList",
                   lm.boundingRect(forGlyphRange:NSRange(location:glyph,length:1),in:tc).contains(point) {
                    let range=(string as NSString).paragraphRange(for:NSRange(location:index,length:0)),old=selectedRange()
                    let replacement=NSMutableAttributedString(attributedString:storage.attributedSubstring(from:range))
                    let done = !(storage.attribute(.npDone,at:index,effectiveRange:nil) as? Bool ?? false)
                    replacement.addAttribute(.npDone,value:done,range:NSRange(location:0,length:replacement.length))
                    let attachment=NSTextAttachment();attachment.attachmentCell=ListMarkerCell(kind:"todoList",done:done)
                    replacement.addAttribute(.attachment,value:attachment,range:NSRange(location:0,length:1))
                    insertText(replacement,replacementRange:range);setSelectedRange(NSRange(location:min(old.location,storage.length),length:0));undoManager?.setActionName("체크 상태 변경");return
                }
            }
        }
        super.mouseDown(with:event)
    }
}

struct StructuredEditor:NSViewRepresentable {
    var document:CloudDocument;var identity:String;var revision:Int;var size:Double;var ratio:Double
    var handle:StructuredEditorHandle;var onChange:(CloudDocument)->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        let view=StructuredTextView(frame:NSRect(x:0,y:0,width:500,height:500));view.isRichText=true;view.allowsUndo=true;view.importsGraphics=false
        view.isVerticallyResizable=true;view.isHorizontallyResizable=false;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true;view.textContainer?.containerSize=NSSize(width:500,height:CGFloat.greatestFiniteMagnitude)
        view.minSize=NSSize(width:0,height:0);view.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude);view.textContainerInset=NSSize(width:24,height:18)
        view.isAutomaticTextReplacementEnabled=false;view.isAutomaticDashSubstitutionEnabled=false;view.isAutomaticQuoteSubstitutionEnabled=false
        view.setAccessibilityLabel("메모 본문");view.delegate=context.coordinator;scroll.documentView=view;handle.view=view
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        let c=context.coordinator;c.parent=self
        guard let view=scroll.documentView as? StructuredTextView else{return};view.size=size;view.ratio=ratio
        let key="\(identity):\(revision):\(size):\(ratio)"
        if c.loaded != key,!view.hasMarkedText() {
            let old=view.selectedRange(),changed=c.identity != identity
            c.updating=true;view.textStorage?.setAttributedString(StructuredCodec.attributed(document,size:size,ratio:ratio));view.typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:size,ratio:ratio)
            view.setSelectedRange(NSRange(location:changed ? 0:min(old.location,view.textStorage?.length ?? 0),length:0));c.updating=false;c.loaded=key;c.identity=identity
            if changed {view.undoManager?.removeAllActions()}
        }
    }
    @MainActor final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:StructuredEditor;var loaded="",identity="",updating=false;let undo=UndoManager()
        init(_ parent:StructuredEditor){self.parent=parent}
        func undoManager(for view:NSTextView)->UndoManager? {undo}
        func textDidChange(_ notification:Notification) {
            guard !updating,let view=notification.object as? StructuredTextView,!view.hasMarkedText() else{return}
            view.refreshNumbers()
            parent.onChange(StructuredCodec.capture(view))
        }
    }
}
