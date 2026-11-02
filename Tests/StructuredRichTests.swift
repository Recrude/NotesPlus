import AppKit
@main struct StructuredRichTests {
    @MainActor static func main()throws {
        _=NSApplication.shared
        struct Fixture:Decodable {var document:CloudDocument}
        let document=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:"build/structured/rich-fixture.json"))).document
        let view=StructuredTextView(frame:NSRect(x:0,y:0,width:700,height:600));view.isRichText=true;view.isEditable=true;view.allowsUndo=true
        let handle=StructuredEditorHandle();let parent=StructuredEditor(document:document,identity:"rich",revision:0,size:17,ratio:1.6,handle:handle,onChange:{_ in})
        let coordinator=StructuredEditor.Coordinator(parent);view.delegate=coordinator
        view.textStorage?.setAttributedString(StructuredCodec.attributed(document,size:17,ratio:1.6))
        let captured=StructuredCodec.capture(view)
        precondition(captured.editorEquivalent(to:document),"Native load/capture retains rich span and image metadata")
        var preferences=Preferences();preferences.fontWeight="semibold";preferences.lineRatio=2;preferences.fontSize=25
        StructuredCodec.applyDisplay(preferences,to:view)
        precondition(StructuredCodec.capture(view).editorEquivalent(to:document),"Display preferences never become source formatting")
        let richPosition=(view.string as NSString).range(of:"색상").location
        precondition((view.textStorage!.attribute(.font,at:richPosition,effectiveRange:nil) as? NSFont)?.pointSize==19,"Explicit source font size remains visible")
        let imagePosition=(view.string as NSString).range(of:"\u{fffc}").location
        view.setSelectedRange(NSRange(location:imagePosition,length:1));let before=view.string;view.insertText("삭제 시도",replacementRange:view.selectedRange());precondition(view.string==before,"Typing/paste cannot replace original attachment")
        view.setSelectedRange(NSRange(location:imagePosition+1,length:0));view.deleteBackward(nil);precondition(view.string==before,"Backspace cannot delete source image")
        view.setSelectedRange(NSRange(location:(view.string as NSString).length,length:0));view.typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:17,ratio:1.6);view.insertText(" 계속 입력",replacementRange:view.selectedRange())
        let edited=StructuredCodec.capture(view);try JSONEncoder().encode(edited).write(to:URL(fileURLWithPath:"build/structured/rich-edited.json"))
        precondition(edited.paragraphs.flatMap(\.spans).compactMap(\.embed).map(\.id)==["fixture-image"])
        var tableP=CloudParagraph(text:"\u{fffc}");tableP.tableID="rich-table"
        let tableDoc=CloudDocument(paragraphs:[tableP,CloudParagraph(text:"본문")],tables:[CloudTable(id:"rich-table",grid:[["서식 셀"]],protected:true)])
        view.textStorage?.setAttributedString(StructuredCodec.attributed(tableDoc,size:17,ratio:1.6));view.setSelectedRange(NSRange(location:0,length:0));view.insertText("보호",replacementRange:view.selectedRange());precondition(view.string.hasPrefix("서식 셀"))
        precondition(StructuredCodec.capture(view).tables[0].protected==true,"Protected rich table state survives native capture")
        print("PASS: rich native round-trip, attachment edit guards, display preferences, protected table/body separation")
    }
}
