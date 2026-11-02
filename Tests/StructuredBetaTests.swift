import AppKit

actor MultiCloud:CloudRequesting {
    var retries=0
    var notes:[String:CloudSnapshot];var calls:[String]=[];var delays:[String:UInt64]=[:]
    init(_ notes:[CloudSnapshot]){self.notes=Dictionary(uniqueKeysWithValues:notes.map{($0.id,$0)})}
    func retryNext(_ count:Int){retries=count}
    func delay(_ id:String,_ n:UInt64){delays[id]=n}
    func saved(_ id:String)->CloudSnapshot{notes[id]!}
    func request<T:Decodable & Sendable>(_ command:String,account:CloudAccount?,payload:[String:Any],as:T.Type)async throws->T {
        let id=payload["id"] as? String ?? "a"
        if command=="save" {
            if retries>0{retries-=1;throw CloudFailure(code:"RETRY",message:"temporary tag race")}
            let desired=try JSONDecoder().decode(CloudDocument.self,from:JSONSerialization.data(withJSONObject:payload["document"]!));calls.append(id)
            try await Task.sleep(nanoseconds:120_000_000)
            var s=notes[id]!;s.document=desired;s.tag="saved-\(calls.count)";notes[id]=s
        }else if let n=delays[id]{try await Task.sleep(nanoseconds:n)}
        return try JSONDecoder().decode(T.self,from:JSONEncoder().encode(notes[id]!))
    }
}
@main struct StructuredBetaTests {
    @MainActor static func main()async throws {
        _=NSApplication.shared
        func snap(_ id:String,_ text:String)->CloudSnapshot{CloudSnapshot(id:id,title:id,tag:"base-"+id,document:CloudDocument(paragraphs:[CloudParagraph(text:text)]),created:0)}
        let a=snap("a","A 원본"),b=snap("b","B 원본"),c=snap("c","C 원본")
        let backend=MultiCloud([a,b,c]),account=CloudAccount(session:CloudSession(cookie:"fixture",clientId:"fixture",clientBuildNumber:"fixture",clientMasteringNumber:"fixture",capturedAt:"fixture"),dsid:"fixture",host:"fixture")
        let support=FileManager.default.temporaryDirectory.appendingPathComponent("notesplus-beta-\(UUID().uuidString)");defer{try? FileManager.default.removeItem(at:support)}
        let model=StructuredModel(client:backend,account:account,startTasks:false,support:support)
        model.snapshot=a;model.document=a.document
        let full=CloudDocument(paragraphs:[CloudParagraph(text:"A의 완전한 입력 😀")]);model.edited(full)
        let save=Task{await model.save()};try await Task.sleep(for:.milliseconds(20));await model.select("b");await save.value
        precondition(model.snapshot?.id=="b" && model.document==b.document,"A save cannot install into B")
        let savedA=await backend.saved("a");precondition(savedA.document==full,"A saves while another note is active")
        await model.select("a");precondition(!model.dirty && model.document==full,"Return uses acknowledged A state")
        let race=StructuredModel(client:backend,account:account,startTasks:false,support:support.appendingPathComponent("race"))
        await backend.delay("a",180_000_000);await backend.delay("b",20_000_000)
        let slow=Task{await race.select("a")};try await Task.sleep(for:.milliseconds(10));await race.select("b");await slow.value
        precondition(race.snapshot?.id=="b","Late selection response never changes requested note")
        await backend.delay("a",0);await backend.delay("b",0)
        await backend.retryNext(2)
        race.edited(CloudDocument(paragraphs:[CloudParagraph(text:"재시도 중에도 온전한 본문")]))
        await race.save();precondition(!race.dirty && race.conflict==nil,"Tag-only races retry without false user conflict")
        await backend.delay("b",120_000_000)
        try await Task.sleep(for:.seconds(3.1))
        let prior=race.document;let pendingRead=Task{await race.refresh()};try await Task.sleep(for:.milliseconds(10));race.inputBegan();await pendingRead.value
        precondition(race.document==prior && race.pendingInput,"Typing that starts during refresh prevents replacement")
        var offsets=a.document;offsets.paragraphs[0].start=91;offsets.paragraphs[0].separator=""
        precondition(a.document.editorEquivalent(to:offsets),"Wire offsets and terminal separator cannot reinstall the editor")
        precondition(StructuredCodec.remap(NSRange(location:5,length:0),from:"hello",to:"prefix hello").location==12,"Caret at end stays at end after remote formatting")
        // A real AppKit marked-text session must not enter the save document.
        let handle=StructuredEditorHandle();var captured:[CloudDocument]=[];var began=0
        let parent=StructuredEditor(document:a.document,identity:"input",revision:0,size:17,ratio:1.6,handle:handle,onChange:{captured.append($0)},onInput:{began+=1})
        let coordinator=StructuredEditor.Coordinator(parent)
        let view=StructuredTextView(frame:NSRect(x:0,y:0,width:700,height:600));view.isRichText=true;view.allowsUndo=true;view.delegate=coordinator
        view.typingAttributes=StructuredCodec.attributes(CloudParagraph(),size:17,ratio:1.6)
        view.setMarkedText("ㅎ",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0));coordinator.flush(view)
        precondition(captured.isEmpty && view.hasMarkedText(),"Composition never captured mid-syllable")
        view.setMarkedText("한글",selectedRange:NSRange(location:2,length:0),replacementRange:NSRange(location:NSNotFound,length:0));coordinator.flush(view);precondition(captured.isEmpty)
        view.insertText("한글",replacementRange:NSRange(location:NSNotFound,length:0));coordinator.flush(view)
        precondition(captured.last?.paragraphs.first?.text=="한글","Committed composition captured once")
        captured.removeAll();let big=String(repeating:"한글 입력과 기존 본문 😀\n",count:1500)
        view.textStorage?.setAttributedString(NSAttributedString(string:big,attributes:StructuredCodec.attributes(CloudParagraph(),size:17,ratio:1.6)));view.setSelectedRange(NSRange(location:(big as NSString).length,length:0))
        var timings:[Double]=[]
        for _ in 0..<200{let start=CFAbsoluteTimeGetCurrent();view.insertText("a",replacementRange:view.selectedRange());timings.append((CFAbsoluteTimeGetCurrent()-start)*1000)}
        precondition(captured.isEmpty,"Keystrokes do not synchronously capture the whole document")
        try await Task.sleep(for:.milliseconds(400));coordinator.flush(view)
        precondition(captured.count==1 && view.string==big+String(repeating:"a",count:200),"One coalesced capture preserves all rapid typing")
        let sorted=timings.sorted();print(String(format:"INPUT BENCH: %d UTF-16 units, 200 inserts, p95 %.2f ms, max %.2f ms, captures %d",(big as NSString).length,sorted[190],sorted.last!,captured.count))
        // Local font preferences cannot become bold/italic in the document.
        let rich=CloudDocument(paragraphs:[CloudParagraph(text:"보통 본문"),CloudParagraph(text:"기울임")])
        var styled=rich;styled.paragraphs[1].spans[0].italic=true
        view.textStorage?.setAttributedString(StructuredCodec.attributed(styled,size:17,ratio:1.6));var prefs=Preferences();prefs.fontWeight="semibold";prefs.lineRatio=2
        StructuredCodec.applyDisplay(prefs,to:view)
        precondition(StructuredCodec.capture(view).paragraphs.map(\.spans)==styled.paragraphs.map(\.spans),"Local display options preserve semantic formatting")
        view.textStorage?.setAttributedString(StructuredCodec.attributed(a.document,size:17,ratio:1.6));view.setSelectedRange(NSRange(location:view.textStorage!.length,length:0));view.insertTable()
        var tableDoc=StructuredCodec.capture(view);precondition(tableDoc.tables.count==1 && tableDoc.tables[0].grid==[["",""],["",""]],"Insert actual 2x2 table")
        view.resizeTable("row+");tableDoc=StructuredCodec.capture(view);precondition(tableDoc.tables[0].grid.count==3)
        view.resizeTable("column+");tableDoc=StructuredCodec.capture(view);precondition(tableDoc.tables[0].grid[0].count==3)
        precondition(tableDoc.paragraphs.first?.text=="A 원본","Table operations preserve body")
        print("PASS: per-note saves, selection races, marked text, coalesced long-note typing, display-only settings, table controls")
    }
}
