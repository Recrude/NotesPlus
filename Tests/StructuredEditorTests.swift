import AppKit

@main struct StructuredEditorTests {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let view=StructuredTextView(frame:NSRect(x:0,y:0,width:700,height:600));view.isRichText=true;view.allowsUndo=true
        var todo=CloudParagraph(text:"한글 😀 체크",kind:"todoList");todo.done=true
        var table=CloudParagraph(text:"\u{fffc}");table.tableID="table-1"
        var bold=CloudParagraph(text:"굵은 본문");bold.spans[0].bold=true;bold.spans[0].underline=true
        var heading=CloudParagraph(text:"제목",kind:"title");heading.spans[0].bold=true
        let original=CloudDocument(paragraphs:[heading,bold,CloudParagraph(text:"글머리",kind:"bulletList"),todo,table,CloudParagraph(text:"표 다음 본문")],tables:[CloudTable(id:"table-1",grid:[["한글","😀"],["여러\n줄","보존"]])])
        view.textStorage!.setAttributedString(StructuredCodec.attributed(original,size:17,ratio:1.6))
        let captured=StructuredCodec.capture(view)
        precondition(captured.paragraphs.map(\.text)==original.paragraphs.map(\.text),"Mixed body preservation")
        precondition(captured.paragraphs.map(\.kind)==original.paragraphs.map(\.kind),"Paragraph kinds")
        precondition(captured.paragraphs[3].done==true,"Checklist state")
        precondition(captured.tables==original.tables,"Table cells and multiline text")
        precondition(captured.paragraphs[1].spans==bold.spans,"Inline formatting")
        precondition(captured.paragraphs[0].spans==heading.spans,"Explicit heading emphasis survives")
        let beforeTable=(view.string as NSString).range(of:"글머리")
        view.setSelectedRange(beforeTable);view.setParagraphKind("numberedList")
        let converted=StructuredCodec.capture(view)
        precondition(converted.paragraphs.map(\.text)==original.paragraphs.map(\.text),"Formatting before table must retain entire trailing body")
        precondition(converted.tables==original.tables,"Formatting before table must retain table")
        let index=(view.string as NSString).range(of:"한글 😀 체크").location
        view.setSelectedRange(NSRange(location:index+("한글 😀 체크" as NSString).length,length:0));view.insertNewline(nil);view.insertText("다음 항목",replacementRange:view.selectedRange())
        let continued=StructuredCodec.capture(view)
        precondition(continued.paragraphs[4].kind=="todoList" && continued.paragraphs[4].done==false && continued.paragraphs[4].text=="다음 항목","Checklist Return continues unchecked")
        precondition(continued.tables==original.tables,"Editing before a table preserves it")
        let content=(view.string as NSString).range(of:"표 다음 본문")
        view.setSelectedRange(content);view.setParagraphKind("numberedList")
        let numbered=StructuredCodec.capture(view)
        precondition(numbered.paragraphs.last?.kind=="numberedList","Toolbar changes actual structure")
        let typing=StructuredTextView(frame:.zero);typing.isRichText=true
        typing.typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:17,ratio:1.6)
        typing.insertText("1.",replacementRange:typing.selectedRange());typing.insertText(" ",replacementRange:typing.selectedRange());typing.insertText("첫 항목",replacementRange:typing.selectedRange())
        typing.insertNewline(nil);typing.insertText("두 번째",replacementRange:typing.selectedRange());typing.refreshNumbers()
        let list=StructuredCodec.capture(typing)
        precondition(list.paragraphs.count==2 && list.paragraphs.allSatisfy{$0.kind=="numberedList"},"Automatic ordered list and continuation")
        let second=(typing.string as NSString).paragraphRange(for:NSRange(location:(typing.string as NSString).length,length:0))
        let marker=typing.textStorage!.attribute(.attachment,at:second.location,effectiveRange:nil) as! NSTextAttachment
        precondition((marker.attachmentCell as! ListMarkerCell).number==2,"Visible numbering increments")
        typing.textStorage!.setAttributedString(NSAttributedString(string:"",attributes:StructuredCodec.attributes(CloudParagraph(),size:17,ratio:1.6)));typing.setSelectedRange(NSRange(location:0,length:0));typing.typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:17,ratio:1.6)
        typing.insertText("*",replacementRange:typing.selectedRange());typing.insertText(" ",replacementRange:typing.selectedRange())
        precondition(typing.string=="* " && StructuredCodec.capture(typing).paragraphs[0].kind=="body","Star-space stays literal")
        print("PASS: mixed native editing, inline formats, checklist continuation, real table cells, list conversion")
    }
}
