import AppKit
import SwiftUI

final class PlainNoteTextView:NSTextView {
    var isPasting=false
    weak var editorSettings:EditorSettings?
    var pagePadding=20.0
    var pageWidth=0.0
    @objc func insertTimestamp(_ sender:Any?) {
        insertTimestamp(at:Date())
    }
    func insertTimestamp(at date:Date) {
        guard isEditable,!hasMarkedText(),let settings=editorSettings else{return}
        let stamp=TimestampFormat.string(date:date,format:settings.timestampFormat)
        guard !stamp.isEmpty else{return}
        breakUndoCoalescing()
        insertText(stamp,replacementRange:selectedRange())
        undoManager?.setActionName("타임스탬프 삽입")
        breakUndoCoalescing()
    }
    override func paste(_ sender:Any?) {isPasting=true; defer{isPasting=false}; super.pasteAsPlainText(sender)}
    override func pasteAsPlainText(_ sender:Any?) {isPasting=true; defer{isPasting=false}; super.pasteAsPlainText(sender)}
    override func setFrameSize(_ newSize:NSSize) {super.setFrameSize(newSize); updatePageInsets()}
    func updatePageInsets() {
        let horizontal=pageWidth>0 ? max(pagePadding,(bounds.width-pageWidth)/2) : pagePadding
        if abs(textContainerInset.width-horizontal)>0.1 {textContainerInset.width=horizontal}
    }
}

struct NoteEditor:NSViewRepresentable {
    var text:String
    var noteID:String
    @ObservedObject var settings:EditorSettings
    var titleTemplate:String? = nil
    var document:NoteDocument? = nil
    var loadVersion:UInt = 0
    var bridge:EditorBridge? = nil
    var editable:Bool
    var focusToken:UUID
    var onChange:(String,Bool)->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView(); scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true; scroll.drawsBackground=true
        scroll.backgroundColor = .textBackgroundColor
        let view=PlainNoteTextView(usingTextLayoutManager:true)
        view.editorSettings=settings
        view.textContentStorage?.includesTextListMarkers=false
        view.isRichText=true; view.importsGraphics=false; view.allowsUndo=true; view.usesFontPanel=false
        view.isHorizontallyResizable=false; view.isVerticallyResizable=true; view.autoresizingMask=[.width]
        view.minSize=NSSize(width:0,height:0); view.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView=true; view.textContainerInset=NSSize(width:20,height:5)
        view.setAccessibilityLabel("메모 본문")
        view.delegate=context.coordinator; scroll.documentView=view; context.coordinator.view=view
        bridge?.capture = { [weak view] in view.map{RichTextBridge.capture($0)} ?? NoteDocument(text:"") }
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        let c=context.coordinator; c.parent=self
        guard let view=scroll.documentView as? NSTextView else{return}
        (view as? PlainNoteTextView)?.editorSettings=settings
        view.isEditable=editable; view.isSelectable=true
        // Only a navigation/remote install can replace the editor. Autosave never does.
        if !view.hasMarkedText(),c.noteID != noteID || c.loadedVersion != loadVersion {
            let changedNote=c.noteID != noteID; let oldSelection=view.selectedRange()
            let (contents,typing)=RichTextBridge.attributed(document ?? NoteDocument(text:text),settings:settings)
            c.updating=true; view.textStorage?.setAttributedString(contents); view.typingAttributes=typing
            view.setSelectedRange(changedNote ? NSRange(location:0,length:0) : NSRange(location:min(oldSelection.location,contents.length),length:0))
            c.updating=false; view.undoManager?.removeAllActions()
            if changedNote {view.scrollToBeginningOfDocument(nil)}
            c.noteID=noteID; c.loadedVersion=loadVersion; c.applyStyle(force:true)
            bridge?.noteID=noteID; bridge?.loadVersion=loadVersion
        }
        c.applyInputSettings(); c.applyStyle()
        if c.focusToken != focusToken,editable {
            c.focusToken=focusToken
            DispatchQueue.main.async {if view.window != nil {view.window?.makeFirstResponder(view)}}
        }
    }
    @MainActor final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:NoteEditor; weak var view:NSTextView?
        var updating=false; var noteID=""; var loadedVersion:UInt?; var styleKey=""
        var focusToken:UUID?; var wasComposing=false
        private var appliedInput:Preferences?
        private var changedRange=NSRange(location:0,length:0)
        private let editingUndoManager=UndoManager()
        private(set) var fullStylePasses=0
        init(_ parent:NoteEditor) {self.parent=parent}
        func undoManager(for view:NSTextView)->UndoManager? {editingUndoManager}
        func lists(at location:Int)->[NSTextList] {
            guard let view else{return []}
            let attrs=location < (view.textStorage?.length ?? 0) ? view.textStorage!.attributes(at:location,effectiveRange:nil) : view.typingAttributes
            return (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        }
        func applyStyle(force:Bool=false) {
            guard let view,!view.hasMarkedText() else{return}
            let s=parent.settings
            let key="\(s.fontName)|\(s.fontWeight)|\(s.fontSize)|\(s.lineRatio)|\(s.paragraphSpacing)|\(s.characterSpacing)|\(s.tabWidth)|\(parent.titleTemplate ?? "")"
            guard force || key != styleKey else{return}
            styleKey=key; fullStylePasses += 1
            guard let storage=view.textStorage else{return}
            let enabled=editingUndoManager.isUndoRegistrationEnabled
            if enabled {editingUndoManager.disableUndoRegistration()}
            updating=true
            let copy=storage.copy() as! NSAttributedString
            storage.beginEditing()
            copy.enumerateAttribute(.paragraphStyle,in:NSRange(location:0,length:copy.length)) {value,range,_ in
                let lists=(value as? NSParagraphStyle)?.textLists ?? []
                storage.setAttributes(RichTextBridge.attributes(settings:s,lists:lists),range:range)
            }
            storage.endEditing(); updating=false
            if enabled {editingUndoManager.enableUndoRegistration()}
            styleTitle(); refreshTyping()
        }
        private func styleTitle() {
            guard parent.titleTemplate != nil,let view,let storage=view.textStorage,storage.length>0,lists(at:0).isEmpty else{return}
            // Only the first paragraph is touched, and only while editing that paragraph.
            let first=(view.string as NSString).paragraphRange(for:NSRange(location:0,length:0))
            let template=parent.titleTemplate ?? ""; let s=parent.settings
            let size=s.fontSize+(template.contains("h1") ? 7 : (template.contains("h2") ? 4 : 2))
            let p=s.paragraph.mutableCopy() as! NSMutableParagraphStyle; p.minimumLineHeight=size*s.lineRatio; p.maximumLineHeight=size*s.lineRatio
            let enabled=editingUndoManager.isUndoRegistrationEnabled
            if enabled {editingUndoManager.disableUndoRegistration()}
            updating=true; storage.addAttributes([.font:NSFont.systemFont(ofSize:size,weight:.semibold),.paragraphStyle:p],range:first); updating=false
            if enabled {editingUndoManager.enableUndoRegistration()}
        }
        private func refreshTyping() {
            guard let view,!view.hasMarkedText() else{return}
            let caret=view.selectedRange().location
            var attrs=RichTextBridge.attributes(settings:parent.settings,lists:lists(at:caret))
            if parent.titleTemplate != nil,let storage=view.textStorage,storage.length>0,
               caret < (view.string as NSString).paragraphRange(for:NSRange(location:0,length:0)).length,lists(at:0).isEmpty {
                attrs=storage.attributes(at:0,effectiveRange:nil)
            }
            view.typingAttributes=attrs
        }
        func applyInputSettings() {
            guard let view else{return}
            let p=parent.settings.values
            guard appliedInput != p else{return}; appliedInput=p
            view.isContinuousSpellCheckingEnabled=p.spellChecking; view.isGrammarCheckingEnabled=p.spellChecking && p.grammarChecking
            view.isAutomaticSpellingCorrectionEnabled=p.spellingCorrection; view.isAutomaticQuoteSubstitutionEnabled=p.smartQuotes
            view.isAutomaticDashSubstitutionEnabled=p.smartDashes; view.isAutomaticTextReplacementEnabled=p.textReplacement
            view.isAutomaticTextCompletionEnabled=p.textCompletion; view.smartInsertDeleteEnabled=p.smartInsertDelete
            view.appearance=p.useDarkBackground ? nil : NSAppearance(named:.aqua); view.enclosingScrollView?.appearance=view.appearance
            if let page=view as? PlainNoteTextView {
                page.pagePadding=p.horizontalPadding; page.pageWidth=p.readableWidth
                page.textContainerInset.height=p.verticalPadding; page.updatePageInsets()
            }
        }
        // A bounded attributed replacement gives structural edits a real undo/redo action.
        func replace(_ range:NSRange,with content:NSAttributedString,selection:NSRange,typing:[NSAttributedString.Key:Any]) {
            guard let view,let storage=view.textStorage,NSMaxRange(range)<=storage.length else{return}
            let before=storage.attributedSubstring(from:range); let beforeSelection=view.selectedRange(); let beforeTyping=view.typingAttributes
            view.breakUndoCoalescing()
            editingUndoManager.registerUndo(withTarget:self) {target in
                target.replace(NSRange(location:range.location,length:content.length),with:before,selection:beforeSelection,typing:beforeTyping)
            }
            updating=true; storage.replaceCharacters(in:range,with:content)
            view.setSelectedRange(selection); view.didChangeText(); view.typingAttributes=typing; updating=false
            changedRange=range; didEdit(); view.breakUndoCoalescing()
        }
        private func didEdit() {
            guard let view else{return}
            wasComposing=view.hasMarkedText()
            if !wasComposing,changedRange.location <= (view.string as NSString).paragraphRange(for:NSRange(location:0,length:0)).length {styleTitle()}
            if !wasComposing {refreshTyping()}
            parent.onChange(view.string,wasComposing)
        }
        func textView(_ textView:NSTextView,shouldChangeTextIn range:NSRange,replacementString:String?)->Bool {
            guard !updating else{return true}
            changedRange=range
            guard parent.editable,!textView.hasMarkedText(),!editingUndoManager.isUndoing,!editingUndoManager.isRedoing,
                  (textView as? PlainNoteTextView)?.isPasting != true,replacementString==" ",range.length==0,
                  lists(at:range.location).isEmpty else{return true}
            let ns=textView.string as NSString; let paragraph=ns.paragraphRange(for:range)
            let prefix=ns.substring(with:NSRange(location:paragraph.location,length:range.location-paragraph.location))
            guard let trigger=ListRules.trigger(prefix,preferences:parent.settings.values),trigger.ordered else{return true}
            var suffix=ns.substring(with:NSRange(location:range.location,length:NSMaxRange(paragraph)-range.location))
            if !suffix.hasSuffix("\n") {suffix += "\n"}
            let list=NSTextList(markerFormat:trigger.ordered ? NSTextList.MarkerFormat(rawValue:"{decimal}.") : (trigger.kind=="dash" ? .hyphen : (trigger.kind=="circle" ? .circle : .disc)),options:[],startingItemNumber:trigger.start)
            let attrs=RichTextBridge.attributes(settings:parent.settings,lists:[list])
            replace(paragraph,with:NSAttributedString(string:suffix,attributes:attrs),selection:NSRange(location:paragraph.location,length:0),typing:attrs)
            return false
        }
        func textView(_ textView:NSTextView,doCommandBy command:Selector)->Bool {
            guard !updating,parent.editable,!textView.hasMarkedText() else{return false}
            let name=NSStringFromSelector(command); let selected=textView.selectedRange(); let ns=textView.string as NSString
            let paragraph=ns.paragraphRange(for:selected); let stack=lists(at:selected.location)
            if name=="insertNewline:",!stack.isEmpty,selected.length==0 {
                let line=ns.substring(with:paragraph).trimmingCharacters(in:.newlines)
                if line.trimmingCharacters(in:.whitespaces).isEmpty,parent.settings.exitEmptyList {
                    let attrs=RichTextBridge.attributes(settings:parent.settings,lists:Array(stack.dropLast()))
                    let tail=NSMaxRange(paragraph)<=ns.length && ns.substring(with:paragraph).hasSuffix("\n") ? "\n" : ""
                    replace(paragraph,with:NSAttributedString(string:tail,attributes:attrs),selection:NSRange(location:paragraph.location,length:0),typing:attrs)
                } else {
                    let next=stack.last?.isOrdered==true || parent.settings.continueBullets ? stack : []
                    let before=ns.substring(with:NSRange(location:paragraph.location,length:selected.location-paragraph.location))
                    let after=ns.substring(with:NSRange(location:selected.location,length:NSMaxRange(paragraph)-selected.location))
                    let combined=NSMutableAttributedString(string:before+"\n",attributes:RichTextBridge.attributes(settings:parent.settings,lists:stack))
                    let attrs=RichTextBridge.attributes(settings:parent.settings,lists:next)
                    combined.append(NSAttributedString(string:after,attributes:attrs))
                    replace(paragraph,with:combined,selection:NSRange(location:selected.location+1,length:0),typing:attrs)
                }
                return true
            }
            if name=="insertTab:",parent.settings.tabInsertsSpaces {
                let attrs=textView.typingAttributes
                replace(selected,with:NSAttributedString(string:String(repeating:" ",count:parent.settings.tabWidth),attributes:attrs),selection:NSRange(location:selected.location+parent.settings.tabWidth,length:0),typing:attrs); return true
            }
            if name=="insertNewline:",stack.isEmpty,parent.settings.preserveIndent {
                var p=parent.settings.values; p.numberPeriod=false; p.numberParen=false; p.continueBullets=false
                if let edit=ListRules.newline(text:textView.string,selection:selected,preferences:p) {
                    let attrs=RichTextBridge.attributes(settings:parent.settings)
                    replace(edit.range,with:NSAttributedString(string:edit.replacement,attributes:attrs),selection:NSRange(location:edit.range.location+edit.replacement.utf16.count,length:0),typing:attrs); return true
                }
            }
            return false
        }
        func textDidChange(_ notification:Notification) {guard !updating else{return}; didEdit()}
        func textViewDidChangeSelection(_ notification:Notification) {
            guard !updating,let view else{return}
            if wasComposing,!view.hasMarkedText() {wasComposing=false; parent.onChange(view.string,false)}
        }
    }
}
