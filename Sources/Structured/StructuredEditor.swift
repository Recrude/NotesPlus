import AppKit
import SwiftUI

extension NSAttributedString.Key {
    static let npKind=Self("NotesPlus.kind"),npDone=Self("NotesPlus.done"),npIndent=Self("NotesPlus.indent"),npNumber=Self("NotesPlus.number"),npQuote=Self("NotesPlus.quote"),npTable=Self("NotesPlus.table"),npRow=Self("NotesPlus.row"),npColumn=Self("NotesPlus.column")
    static let npInlineBold=Self("NotesPlus.inlineBold"),npInlineItalic=Self("NotesPlus.inlineItalic")
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
    var flushPending:(()->Void)?
    var focusOnLoad=false
    func flush(){flushPending?()}
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
        return [.font:font,.foregroundColor:NSColor.labelColor,.paragraphStyle:style,.npKind:p.kind,.npDone:p.done ?? false,.npIndent:p.indent,.npNumber:p.startNumber,.npQuote:p.blockQuoteLevel,.npInlineBold:false,.npInlineItalic:false]
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
                extras[.npInlineBold]=span.bold;extras[.npInlineItalic]=span.italic
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
                    let span=CloudSpan(length:r.length,bold:a[.npInlineBold] as? Bool ?? traits.contains(.boldFontMask),italic:a[.npInlineItalic] as? Bool ?? traits.contains(.italicFontMask),underline:(a[.underlineStyle] as? Int ?? 0)>0,strikethrough:(a[.strikethroughStyle] as? Int ?? 0)>0,link:(a[.link] as? URL)?.absoluteString ?? a[.link] as? String ?? "")
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
    var preferences=Preferences()
    var structuralEditing=false
    @objc func insertTimestamp(_ sender:Any?){guard isEditable,!hasMarkedText() else{return};insertText(TimestampFormat.string(format:preferences.timestampFormat),replacementRange:selectedRange())}
    var onChange:(()->Void)?
    private var converting=false
    override func paste(_ sender:Any?) {super.pasteAsPlainText(sender)}
    func paragraphRange()->NSRange {(string as NSString).paragraphRange(for:NSRange(location:min(selectedRange().location,(string as NSString).length),length:0))}
    func attrsAtCaret()->[NSAttributedString.Key:Any] {let at=selectedRange().location;return at<(textStorage?.length ?? 0) ? textStorage!.attributes(at:at,effectiveRange:nil):typingAttributes}
    override func insertText(_ insertString:Any,replacementRange:NSRange) {
        super.insertText(insertString,replacementRange:replacementRange)
        guard isEditable,!converting,!hasMarkedText(),(insertString as? String)==" ",attrsAtCaret()[.npTable]==nil else{return}
        let range=paragraphRange(),line=(string as NSString).substring(with:range).trimmingCharacters(in:.newlines)
        var kind:String?,number=1
        if (preferences.numberPeriod && line.range(of:"^[0-9]{1,6}\\. $",options:.regularExpression) != nil) || (preferences.numberParen && line.range(of:"^[0-9]{1,6}\\) $",options:.regularExpression) != nil) {number=Int(line.dropLast(2)) ?? 0;if number>0{kind="numberedList"}}
        if line=="* " && preferences.starBullet || line=="+ " && preferences.plusBullet {kind="bulletList"}
        if line=="- " && preferences.dashBullet {kind="dashList"}
        guard let kind else{return}
        converting=true;defer{converting=false}
        var p=CloudParagraph(kind:kind);p.startNumber=kind=="numberedList" ? number:0
        let attrs=StructuredCodec.attributes(p,size:size,ratio:ratio)
        super.insertText(StructuredCodec.prefix(kind:p.kind,done:false,number:number,attributes:attrs),replacementRange:NSRange(location:range.location,length:(line as NSString).length));typingAttributes=attrs
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
                if a[.npTable] as? String != id || a[.npRow] as? Int != row || a[.npColumn] as? Int != col {setSelectedRange(NSRange(location:at,length:0));typingAttributes=a;return}
                at=NSMaxRange((string as NSString).paragraphRange(for:NSRange(location:at,length:0)))
            }
            setSelectedRange(NSRange(location:storage.length,length:0));typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:size,ratio:ratio);return
        }
        if preferences.tabInsertsSpaces {insertText(String(repeating:" ",count:preferences.tabWidth),replacementRange:selectedRange())}else{super.insertTab(sender)}
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
        guard isEditable,!hasMarkedText() else{return}
        let selection=selectedRange(),range=(string as NSString).paragraphRange(for:selection)
        var containsTable=false
        textStorage?.enumerateAttribute(.npTable,in:range){value,_,_ in if value != nil {containsTable=true}}
        guard !containsTable else{return}
        let slice=NSTextView();slice.textStorage?.setAttributedString(attributedSubstring(forProposedRange:range,actualRange:nil) ?? NSAttributedString(string:""))
        var document=StructuredCodec.capture(slice)
        if document.paragraphs.last?.text.isEmpty==true,document.paragraphs.count>1 {document.paragraphs.removeLast()}
        for i in document.paragraphs.indices where document.paragraphs[i].tableID==nil {let old=document.paragraphs[i];document.paragraphs[i].kind=kind;document.paragraphs[i].done=kind=="todoList" ? (old.done ?? false):nil;document.paragraphs[i].startNumber=0}
        let replacement=NSMutableAttributedString(attributedString:StructuredCodec.attributed(document,size:size,ratio:ratio))
        if range.length>0,(string as NSString).substring(with:range).hasSuffix("\n") {replacement.append(NSAttributedString(string:"\n",attributes:StructuredCodec.attributes(document.paragraphs.last ?? CloudParagraph(),size:size,ratio:ratio)))}
        if replacement.length==0 && kind.hasSuffix("List") {replacement.append(StructuredCodec.prefix(kind:kind,done:false,number:1,attributes:StructuredCodec.attributes(CloudParagraph(kind:kind),size:size,ratio:ratio)))}
        insertText(replacement,replacementRange:range)
        if replacement.length==0 {typingAttributes=StructuredCodec.attributes(CloudParagraph(kind:kind),size:size,ratio:ratio)}
        window?.makeFirstResponder(self)
        undoManager?.setActionName("문단 서식")
    }
    func toggleInline(_ key:String) {
        guard isEditable,!hasMarkedText() else{return}
        let range=selectedRange();var attrs=attrsAtCaret()
        guard attrs[.npTable]==nil else{NSSound.beep();return}
        if key=="bold" || key=="italic" {
            let font=attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize:size),trait:NSFontTraitMask=key=="bold" ? .boldFontMask:.italicFontMask
            let enabled=key=="bold" ? (attrs[.npInlineBold] as? Bool ?? false):NSFontManager.shared.traits(of:font).contains(trait)
            attrs[.font]=enabled ? NSFontManager.shared.convert(font,toNotHaveTrait:trait):NSFontManager.shared.convert(font,toHaveTrait:trait)
            if key=="bold" {attrs[.npInlineBold] = !enabled}else{attrs[.npInlineItalic] = !enabled}
        }else{attrs[.underlineStyle]=(attrs[.underlineStyle] as? Int ?? 0)>0 ? 0:1}
        if range.length==0 {typingAttributes=attrs}else{
            let content=NSMutableAttributedString(attributedString:attributedString().attributedSubstring(from:range))
            let target=key=="bold" ? attrs[.npInlineBold] as? Bool ?? false:attrs[.npInlineItalic] as? Bool ?? false
            if key=="underline" {content.addAttribute(.underlineStyle,value:attrs[.underlineStyle]!,range:NSRange(location:0,length:content.length))}
            else {
                var updates:[(NSRange,NSFont)]=[];let trait:NSFontTraitMask=key=="bold" ? .boldFontMask:.italicFontMask
                content.enumerateAttribute(.font,in:NSRange(location:0,length:content.length)){value,r,_ in let font=value as? NSFont ?? NSFont.systemFont(ofSize:size);updates.append((r,target ? NSFontManager.shared.convert(font,toHaveTrait:trait):NSFontManager.shared.convert(font,toNotHaveTrait:trait)))}
                for (r,font) in updates {content.addAttribute(.font,value:font,range:r)}
                content.addAttribute(key=="bold" ? .npInlineBold:.npInlineItalic,value:target,range:NSRange(location:0,length:content.length))
            }
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
            if line=="\u{fffc}\t" && preferences.exitEmptyList {setParagraphKind("body");return}
            if kind != "numberedList" && !preferences.continueBullets {super.insertNewline(sender);typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:size,ratio:ratio);return}
            var p=CloudParagraph(kind:kind);p.indent=attrs[.npIndent] as? Int ?? 0;p.done=false
            let next=StructuredCodec.attributes(p,size:size,ratio:ratio)
            let content=NSMutableAttributedString(string:"\n",attributes:attrs)
            content.append(StructuredCodec.prefix(kind:kind,done:false,number:1,attributes:next));insertText(content,replacementRange:selectedRange());typingAttributes=next
        }else {
            let leading=preferences.preserveIndent ? String((string as NSString).substring(with:paragraphRange()).prefix{ $0==" " || $0=="\t" }):""
            super.insertNewline(sender);typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:size,ratio:ratio)
            if !leading.isEmpty{insertText(leading,replacementRange:selectedRange())}
        }
    }
    override func mouseDown(with event:NSEvent) {
        if isEditable,let lm=layoutManager,let tc=textContainer,let storage=textStorage {
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
    var preferences=Preferences();var editable=true;var onInput:(()->Void)?
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        let view=StructuredTextView(frame:NSRect(x:0,y:0,width:500,height:500));view.isRichText=true;view.allowsUndo=true;view.importsGraphics=false
        view.isVerticallyResizable=true;view.isHorizontallyResizable=false;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true;view.textContainer?.containerSize=NSSize(width:500,height:CGFloat.greatestFiniteMagnitude)
        view.minSize=NSSize(width:0,height:0);view.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("메모 본문");view.delegate=context.coordinator;scroll.documentView=view;handle.view=view
        handle.flushPending={[weak c=context.coordinator,weak view] in if let view{c?.flush(view)}}
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        let c=context.coordinator;c.parent=self
        guard let view=scroll.documentView as? StructuredTextView else{return}
        view.size=size;view.ratio=ratio;view.preferences=preferences;view.isEditable=editable
        view.isContinuousSpellCheckingEnabled=preferences.spellChecking;view.isGrammarCheckingEnabled=preferences.grammarChecking
        view.isAutomaticSpellingCorrectionEnabled=preferences.spellingCorrection;view.isAutomaticTextReplacementEnabled=preferences.textReplacement
        view.isAutomaticDashSubstitutionEnabled=preferences.smartDashes;view.isAutomaticQuoteSubstitutionEnabled=preferences.smartQuotes
        view.isAutomaticTextCompletionEnabled=preferences.textCompletion;view.smartInsertDeleteEnabled=preferences.smartInsertDelete
        view.textContainerInset=NSSize(width:preferences.horizontalPadding,height:preferences.verticalPadding)
        let key="\(identity):\(revision)",style=preferences
        guard !view.hasMarkedText() else{return}
        if c.loaded != key {
            c.task?.cancel();c.pending=false
            let old=view.selectedRange(),changed=c.identity != identity,origin=scroll.contentView.bounds.origin
            let replacement=StructuredCodec.attributed(document,size:size,ratio:ratio)
            let selection=changed ? NSRange(location:0,length:0):StructuredCodec.remap(old,from:view.string,to:replacement.string)
            c.updating=true;view.textStorage?.setAttributedString(replacement);view.typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:size,ratio:ratio)
            view.setSelectedRange(selection)
            if !changed{scroll.contentView.scroll(to:origin)}
            c.updating=false;c.loaded=key;c.identity=identity;c.style=nil
            // Undo entries contain character offsets into the previous remote version.
            // Retaining them across a replacement can corrupt a different paragraph.
            view.undoManager?.removeAllActions()
            if handle.focusOnLoad {handle.focusOnLoad=false;view.window?.makeFirstResponder(view)}
        }
        if c.style != style {c.updating=true;StructuredCodec.applyDisplay(preferences,to:view);c.updating=false;c.style=style}
    }
    @MainActor final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:StructuredEditor;var loaded="",identity="",updating=false,pending=false;var style:Preferences?;let undo=UndoManager()
        var task:Task<Void,Never>?,firstPending=Date.distantPast
        init(_ parent:StructuredEditor){self.parent=parent}
        func undoManager(for view:NSTextView)->UndoManager? {undo}
        func textViewDidChangeSelection(_ notification:Notification) {
            guard !updating,let view=notification.object as? StructuredTextView,!view.hasMarkedText(),view.selectedRange().length==0,view.selectedRange().location==(view.string as NSString).length,view.string.hasSuffix("\n") else{return}
            view.typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:view.size,ratio:view.ratio)
        }
        func textDidChange(_ notification:Notification) {
            guard !updating,let view=notification.object as? StructuredTextView else{return}
            if !pending{firstPending=Date()};pending=true;parent.onInput?()
            let delay=Date().timeIntervalSince(firstPending)>1 ? 1:250
            task?.cancel();task=Task{[weak self,weak view] in
                try? await Task.sleep(for:.milliseconds(delay))
                guard !Task.isCancelled,let self,let view else{return};self.flush(view)
            }
        }
        func flush(_ view:StructuredTextView) {
            guard pending,!view.hasMarkedText() else{return};task?.cancel();pending=false
            view.refreshNumbers();parent.onChange(StructuredCodec.capture(view))
        }
        func textView(_ textView:NSTextView,shouldChangeTextIn affectedCharRange:NSRange,replacementString:String?)->Bool {
            guard let view=textView as? StructuredTextView,!view.structuralEditing,let storage=view.textStorage,affectedCharRange.length>0 else{return true}
            // Standard deletion/paste cannot cut across cell boundaries. Dedicated
            // table commands preserve cell identities and manage those edits.
            var cells=Set<String>(),hasBody=false
            storage.enumerateAttributes(in:affectedCharRange){a,_,_ in if let id=a[.npTable] as? String {cells.insert("\(id):\(a[.npRow] ?? 0):\(a[.npColumn] ?? 0)")}else{hasBody=true}}
            if cells.count>1 || (!cells.isEmpty && hasBody){NSSound.beep();return false}
            if !cells.isEmpty,(storage.string as NSString).substring(with:affectedCharRange).hasSuffix("\n"),NSMaxRange(affectedCharRange)<storage.length {
                let after=storage.attributes(at:NSMaxRange(affectedCharRange),effectiveRange:nil),before=storage.attributes(at:affectedCharRange.location,effectiveRange:nil)
                if after[.npRow] as? Int != before[.npRow] as? Int || after[.npColumn] as? Int != before[.npColumn] as? Int || after[.npTable] as? String != before[.npTable] as? String{return false}
            }
            return true
        }
    }
}

extension StructuredCodec {
    static func remap(_ selection:NSRange,from old:String,to new:String)->NSRange {
        let a=Array(old.utf16),b=Array(new.utf16)
        var prefix=0,suffix=0
        while prefix<min(a.count,b.count),a[prefix]==b[prefix]{prefix+=1}
        while suffix<min(a.count-prefix,b.count-prefix),a[a.count-1-suffix]==b[b.count-1-suffix]{suffix+=1}
        func position(_ n:Int)->Int {
            if n==a.count{return b.count}
            if n<=prefix{return n}
            if n>=a.count-suffix{return b.count-(a.count-n)}
            return min(b.count-suffix,max(prefix,n))
        }
        let start=position(selection.location),end=position(NSMaxRange(selection))
        return NSRange(location:max(0,start),length:max(0,end-start))
    }
    static func applyDisplay(_ p:Preferences,to view:StructuredTextView) {
        guard let storage=view.textStorage else{return};let range=NSRange(location:0,length:storage.length)
        var changes:[(NSRange,[NSAttributedString.Key:Any])]=[]
        storage.enumerateAttributes(in:range){a,r,_ in
            let kind=a[.npKind] as? String ?? "body",bold=a[.npInlineBold] as? Bool ?? false
            let italic=a[.npInlineItalic] as? Bool ?? false
            let size=p.fontSize+(kind=="title" ? 7:kind=="heading" ? 4:kind=="subheading" ? 2:0)
            let weight:NSFont.Weight=["title","heading","subheading"].contains(kind) || p.fontWeight=="semibold" ? .semibold:p.fontWeight=="medium" ? .medium:.regular
            var font=kind=="monospaced" ? NSFont.monospacedSystemFont(ofSize:size,weight:weight):p.fontName=="system" ? NSFont.systemFont(ofSize:size,weight:weight):NSFont(name:p.fontName,size:size) ?? NSFont.systemFont(ofSize:size,weight:weight)
            if bold {font=NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask)};if italic{font=NSFontManager.shared.convert(font,toHaveTrait:.italicFontMask)}
            let style=(a[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.minimumLineHeight=size*p.lineRatio;style.maximumLineHeight=size*p.lineRatio;style.paragraphSpacing=p.paragraphSpacing
            style.defaultTabInterval=font.pointSize*0.55*Double(p.tabWidth)
            changes.append((r,[.font:font,.paragraphStyle:style,.kern:p.characterSpacing]))
        }
        storage.beginEditing();for (r,a) in changes{storage.addAttributes(a,range:r)};storage.endEditing()
        if view.selectedRange().location<storage.length{view.typingAttributes=storage.attributes(at:view.selectedRange().location,effectiveRange:nil)}
    }
}

extension StructuredTextView {
    func insertTable() {
        guard isEditable,!hasMarkedText(),attrsAtCaret()[.npTable]==nil else{return}
        let id=UUID().uuidString;var p=CloudParagraph(text:"\u{fffc}");p.tableID=id
        let table=CloudDocument(paragraphs:[p,CloudParagraph()],tables:[CloudTable(id:id,grid:[["",""],["",""]])])
        let end=NSMaxRange(paragraphRange()),needsBreak=end>0 && !(string as NSString).substring(with:NSRange(location:end-1,length:1)).contains("\n")
        let content=NSMutableAttributedString(string:needsBreak ? "\n":"",attributes:StructuredCodec.attributes(CloudParagraph(),size:size,ratio:ratio))
        content.append(StructuredCodec.attributed(table,size:size,ratio:ratio))
        structuralEditing=true;defer{structuralEditing=false}
        insertText(content,replacementRange:NSRange(location:end,length:0));setSelectedRange(NSRange(location:end+(needsBreak ? 1:0),length:0))
        typingAttributes=attrsAtCaret();window?.makeFirstResponder(self);undoManager?.setActionName("표 삽입")
    }
    func resizeTable(_ action:String) {
        guard isEditable,!hasMarkedText(),let storage=textStorage,let id=attrsAtCaret()[.npTable] as? String else{return}
        let attrs=attrsAtCaret(),row=attrs[.npRow] as? Int ?? 0,col=attrs[.npColumn] as? Int ?? 0
        let doc=StructuredCodec.capture(self);guard var table=doc.tables.first(where:{$0.id==id}),!table.grid.isEmpty else{return}
        switch action {
        case "row+":table.grid.insert(Array(repeating:"",count:table.grid[0].count),at:min(row+1,table.grid.count))
        case "row-":guard table.grid.count>1 else{return};table.grid.remove(at:row)
        case "column+":for i in table.grid.indices{table.grid[i].insert("",at:min(col+1,table.grid[i].count))}
        case "column-":guard table.grid[0].count>1 else{return};for i in table.grid.indices{table.grid[i].remove(at:col)}
        default:return
        }
        var range:NSRange?;storage.enumerateAttribute(.npTable,in:NSRange(location:0,length:storage.length)){value,r,_ in if value as? String==id{range=range.map{NSUnionRange($0,r)} ?? r}}
        guard let range else{return};var p=CloudParagraph(text:"\u{fffc}");p.tableID=id
        let replacement=StructuredCodec.attributed(CloudDocument(paragraphs:[p],tables:[table]),size:size,ratio:ratio)
        structuralEditing=true;defer{structuralEditing=false};insertText(replacement,replacementRange:range)
        setSelectedRange(NSRange(location:range.location,length:0));typingAttributes=attrsAtCaret();window?.makeFirstResponder(self);undoManager?.setActionName("표 크기 변경")
    }
}
