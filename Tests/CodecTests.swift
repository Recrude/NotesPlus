import Foundation
import AppKit

@main struct CodecTests {
    static var count=0
    static func check(_ value:Bool,_ message:String) {
        guard value else { fatalError("FAIL: \(message)") }
        count += 1; print("PASS: \(message)")
    }
    static func profile(_ html:String,_ plain:String="제목\n본문", locked:Bool=false, shared:Bool=false, attachments:Int=0)->EditingProfile {
        NoteCodec.profile(html:html,plaintext:plain,locked:locked,shared:shared,attachments:attachments)
    }
    static func main() {
        check(profile("<div>제목</div><div>본문</div>").editable,"plain Korean note editable")
        let title=profile("<div><h1>제목</h1></div><div>본문</div>")
        check(title.editable && title.titleTemplate != nil,"native heading retained")
        check(NoteCodec.html(for:"새 제목\n본문",profile:title).contains("<h1>새 제목</h1>"),"title changes preserve heading markup")
        check(profile("<div>제목</div><ol><li>본문</li></ol>").editable,"native numbered list editable")
        check(!profile("<div>제목</div><table><tr><td>본문</td></tr></table>").editable,"table read only")
        check(!profile("<div>제목</div><div><b>본문</b></div>").editable,"formatted body read only")
        check(!profile("",locked:true).editable,"locked note read only")
        check(!profile("",shared:true).editable,"shared note read only")
        check(!profile("",attachments:1).editable,"attachment note read only")
        let html=NoteCodec.html(for:"한글 <태그> & \"기호\"\n* 별표\n\n끝")
        check(html.contains("&lt;태그&gt;") && html.contains("&amp;") && html.contains("&quot;"),"HTML metacharacters escaped")
        check(html.contains("<div>* 별표</div>") && !html.contains("<ul>"),"literal star has no list markup")
        check(html.contains("<div><br></div>"),"empty paragraph preserved")
        check(NoteCodec.html(for:"  들여쓰기  본문 ").contains("&nbsp;&nbsp;들여쓰기&nbsp;&nbsp;본문&nbsp;"),"repeated and boundary spaces preserved")
        check(profile(NoteCodec.html(for:"제목\n\t탭"),"제목\n\t탭").editable,"tab markup remains editable")
        let storage=NSTextStorage(string:"한글 첫째 줄\n한글 둘째 줄\n한글 셋째 줄")
        let layout=NSLayoutManager(); let container=NSTextContainer(size:NSSize(width:600,height:1000))
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        let p=NSMutableParagraphStyle(); p.minimumLineHeight=24; p.maximumLineHeight=24
        storage.addAttributes([.font:NSFont.systemFont(ofSize:15),.paragraphStyle:p],range:NSRange(location:0,length:storage.length))
        layout.ensureLayout(for:container)
        var positions:[CGFloat]=[]
        layout.enumerateLineFragments(forGlyphRange:NSRange(location:0,length:layout.numberOfGlyphs)) { rect,_,_,_,_ in positions.append(rect.minY) }
        check(positions.count==3 && abs(positions[1]-positions[0]-24)<0.01 && abs(positions[2]-positions[1]-24)<0.01,"Korean line pitch 24 pt at 15 pt × 1.6")
        let emptyTitle=profile("<div><h1><br></h1></div>","\n")
        check(emptyTitle.editable && NoteCodec.html(for:"새 제목\n본문",profile:emptyTitle).contains("<h1>새 제목</h1>"),"empty native heading stays editable and accepts first title")
        let canonicalEmpty=profile("<div><b><span style=\"font-size: 18px\"><br></span></b></div>\n","\n")
        check(canonicalEmpty.editable && NoteCodec.html(for:"머리말\n본문",profile:canonicalEmpty).contains("머리말</span>"),"actual Notes empty heading serialization remains editable")
        check(!profile("<div>체크리스트</div><ul><li>체크 상태 보존<br></li></ul>","체크리스트\n체크 상태 보존\n").editable,"ambiguous checklist HTML is protected from destructive flattening")
        let listHTML="<div>목록</div><div>* 별표</div><ol><li><font face=\".AppleSDGothicNeoI-Regular\">첫째</font> 항목<br></li><li>둘째<br></li></ol><div><br></div>"
        let listPlain="목록\n* 별표\n첫째 항목\n둘째\n\n"
        let listProfile=profile(listHTML,listPlain)
        let listDoc=NoteCodec.document(html:listHTML,plaintext:listPlain,profile:listProfile)!
        check(listDoc.paragraphs[2].lists.first?.ordered==true && listDoc.paragraphs[3].lists==listDoc.paragraphs[2].lists,"native Korean list HTML decodes to a shared ordered list")
        let listOutput=NoteCodec.html(for:listDoc)
        check(listOutput.contains("<ol>") && listOutput.contains("<li>첫째 항목</li>") && !listOutput.contains("1. 첫째"),"saving emits real OL/LI without typed numbers")
        let roundTrip=NoteCodec.document(html:listOutput,plaintext:listPlain,profile:profile(listOutput,listPlain))!
        check(listDoc.equivalent(to:roundTrip),"ordered list serialization round trip preserves structure and literal star")
        let nestedHTML="<div>목록</div><ol><li>부모<ol><li>자식</li></ol></li><li>다음</li></ol>"
        let nestedPlain="목록\n부모\n자식\n다음"
        let nested=NoteCodec.document(html:nestedHTML,plaintext:nestedPlain,profile:profile(nestedHTML,nestedPlain))!
        check(nested.paragraphs[2].lists.count==2 && nested.paragraphs[3].lists.count==1,"nested numbered lists retain their hierarchy")
        check(NoteCodec.document(html:NoteCodec.html(for:nested),plaintext:nestedPlain,profile:EditingProfile())!.equivalent(to:nested),"nested numbered lists survive export and reload")
        print("\(count) checks passed.")
    }
}
