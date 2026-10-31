import AppKit
import Foundation
import Combine

actor FakeNotes: NotesBackend {
    var values:[String:NoteSnapshot]
    var writeCount=0
    var createdFolder:String?
    var failures=0
    var delayedReadbacks=0
    var pendingReadbacks:[NoteSnapshot]=[]
    var failAfterWrite=false
    var showCount=0
    var holdWrites=false
    var writeGate:CheckedContinuation<Void,Never>?
    var writeWaiters:[(Int,CheckedContinuation<Void,Never>)]=[]
    var holdRead=false
    var readStarted=false
    var readGate:CheckedContinuation<Void,Never>?
    var readWaiter:CheckedContinuation<Void,Never>?
    init() {
        values=["n1":Self.note("n1","첫 메모\n본문"),"n2":Self.note("n2","둘째 메모\n본문")]
    }
    static func note(_ id:String,_ text:String)->NoteSnapshot {
        NoteSnapshot(["id":id,"name":text.components(separatedBy:"\n").first ?? "","plain":text,"html":NoteCodec.html(for:text),"modified":Date()])
    }
    func folders() async throws->[NoteFolder] { [NoteFolder(["id":"f1","name":"Notes","account":"iCloud","count":2])] }
    func notes(in folder:String) async throws->[NoteSummary] { values.values.map { NoteSummary(["id":$0.id,"name":$0.name,"modified":$0.modified]) } }
    func read(_ id:String) async throws->NoteSnapshot {
        let value=pendingReadbacks.isEmpty ? values[id]! : pendingReadbacks.removeFirst()
        if holdRead {
            holdRead=false; readStarted=true; readWaiter?.resume(); readWaiter=nil
            await withCheckedContinuation { readGate=$0 }
        }
        return value
    }
    func create(in folder:String,html:String) async throws->NoteSnapshot {
        createdFolder=folder
        // Simulate Notes dropping an empty heading during canonicalization.
        let note=Self.note("n3",""); values[note.id]=note; return note
    }
    func show(_ id:String) async throws { showCount += 1 }
    func write(_ id:String,expectedHTML:String,html:String) async throws->NoteSnapshot {
        writeCount += 1
        let ready=writeWaiters.filter{$0.0<=writeCount}; writeWaiters.removeAll{$0.0<=writeCount}; ready.forEach{$0.1.resume()}
        if holdWrites { await withCheckedContinuation { writeGate=$0 } }
        if failures>0 { failures -= 1; throw NSError(domain:"Test",code:503,userInfo:[NSLocalizedDescriptionKey:"Temporary connection failure"]) }
        guard values[id]?.html==expectedHTML else { throw NSError(domain:"Test",code:409,userInfo:[NSLocalizedDescriptionKey:"Changed remotely"]) }
        let previous=values[id]!
        let doc=try XMLDocument(xmlString:html,options:[.documentTidyHTML,.nodeLoadExternalEntitiesNever])
        let plain=try doc.nodes(forXPath:"//body/div | //body/p | //body/ol/li").map{NoteCodec.normalized($0.stringValue ?? "")}.joined(separator:"\n")+"\n"
        let result=NoteSnapshot(["id":id,"name":plain.components(separatedBy:"\n").first ?? "","plain":plain,"html":html,"modified":Date()])
        values[id]=result
        if failAfterWrite {failAfterWrite=false; throw NSError(domain:"Test",code:425,userInfo:[NSLocalizedDescriptionKey:"Readback is still settling"])}
        if delayedReadbacks>0 {
            pendingReadbacks=Array(repeating:previous,count:delayedReadbacks-1); delayedReadbacks=0; return previous
        }
        return result
    }
    func waitForWrites(_ count:Int) async {
        if writeCount>=count { return }
        await withCheckedContinuation { writeWaiters.append((count,$0)) }
    }
    func addIncomingNote() {values["incoming"]=Self.note("incoming","기본 앱에서 새로 만든 메모")}
    func blockWrites() { holdWrites=true }
    func releaseWrites() { holdWrites=false; writeGate?.resume(); writeGate=nil }
    func failOnce() { failures=1 }
    func delayReadback(_ count:Int) {delayedReadbacks=count}
    func failOnceAfterApplying() {failAfterWrite=true}
    func restore(_ note:NoteSnapshot) {values[note.id]=note}
    func externalEdit(_ text:String) { values["n1"]=Self.note("n1",text) }
    func canonicalizeHTML() {
        let old=values["n1"]!
        let html=old.html.contains("<p>") ? old.html.replacingOccurrences(of:"<p>",with:"<div>").replacingOccurrences(of:"</p>",with:"</div>") : old.html.replacingOccurrences(of:"<div>",with:"<p>").replacingOccurrences(of:"</div>",with:"</p>")
        values["n1"]=NoteSnapshot(["id":old.id,"name":old.name,"plain":old.text+"\n","html":html,"modified":Date()])
    }
    func blockNextRead() { holdRead=true; readStarted=false }
    func waitForRead() async { if !readStarted { await withCheckedContinuation { readWaiter=$0 } } }
    func releaseRead() { readGate?.resume(); readGate=nil }
}

@main struct AutosaveTests {
    @MainActor static var checks=0
    @MainActor static var directories:[URL]=[]
    @MainActor static func check(_ okay:Bool,_ message:String) {
        guard okay else { fatalError("FAIL: \(message)") }
        checks += 1; print("PASS: \(message)")
    }
    @MainActor static func make(debounce:UInt64 = 60_000_000_000) async -> (NotesModel,FakeNotes,URL) {
        let backend=FakeNotes()
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("NotesPlusAutosaveTests-\(UUID().uuidString)")
        directories.append(url)
        let model=NotesModel(backend:backend,supportURL:url,startTimer:false,debounceNanoseconds:debounce)
        await model.connect(); await model.chooseNote("n1")
        return (model,backend,url)
    }
    @MainActor static func main() async {
        _ = NSApplication.shared
        Task.detached { try? await Task.sleep(nanoseconds:30_000_000_000); fatalError("Autosave test timeout") }
        do {
            let (m,b,_)=await make(debounce:20_000_000)
            m.edited("자동 저장\n한글 입력")
            await b.waitForWrites(1)
            _ = await m.flush()
            check(NoteCodec.normalized(try await b.read("n1").text)=="자동 저장\n한글 입력","typing starts a write without a save command")
            let count=await b.writeCount
            check(!m.dirty && !m.saving && count==1,"canonical trailing newline does not trigger a save loop")
        } catch { fatalError("\(error)") }
        do {
            let (m,b,url)=await make()
            await b.blockWrites(); m.edited("First edit")
            let save=Task { await m.flush() }
            await b.waitForWrites(1)
            m.edited("Second edit while saving")
            check(m.canEdit && m.text=="Second edit while saving","editor stays usable while a write is in flight")
            await b.releaseWrites(); let ok=await save.value
            let remote=try await b.read("n1").text
            check(ok && !m.dirty && NoteCodec.normalized(remote)=="Second edit while saving","late completion preserves and drains newer typing")
            check(await b.writeCount==2,"one serialized follow-up write uses the new server baseline")
            let backups=try FileManager.default.contentsOfDirectory(at:url.appendingPathComponent("Backups"),includingPropertiesForKeys:nil)
            check(backups.count==1,"continuous typing coalesces backups")
        } catch { fatalError("\(error)") }
        do {
            let (m,b,_)=await make()
            await b.blockWrites(); m.edited("Saved before switching")
            let navigation=Task { await m.chooseNote("n2") }
            await b.waitForWrites(1)
            check(m.switching,"note navigation waits for pending persistence")
            await b.releaseWrites(); await navigation.value
            check(m.selectedNoteID=="n2" && m.text.hasPrefix("둘째 메모"),"switching installs only the selected note")
            check(NoteCodec.normalized(try await b.read("n1").text)=="Saved before switching","leaving a note flushes its final text")
        } catch { fatalError("\(error)") }
        do {
            let (m,b,_)=await make(debounce:20_000_000)
            m.edited("ㅎ",composing:true)
            try await Task.sleep(nanoseconds:70_000_000)
            check(await b.writeCount==0,"IME marked text is not written prematurely")
            m.edited("한글",composing:false)
            await b.waitForWrites(1); _ = await m.flush()
            check(NoteCodec.normalized(try await b.read("n1").text)=="한글","committed Korean text starts autosave")
        } catch { fatalError("\(error)") }
        do {
            let (m,b,url)=await make()
            await b.externalEdit("iPhone modification"); m.edited("Unsaved Mac draft")
            let ok=await m.flush()
            check(!ok && m.hasConflict && m.text=="Unsaved Mac draft","a stale automatic write enters conflict state")
            check(try await b.read("n1").text=="iPhone modification","conflict never overwrites the remote edit")
            let files=try FileManager.default.contentsOfDirectory(atPath:url.path)
            check(files.contains{$0.hasPrefix("draft-")},"conflicting local text is retained on disk")
        } catch { fatalError("\(error)") }
        do {
            let (m,b,_)=await make()
            await b.failOnce(); m.edited("Retry me")
            let failed=await m.flush()
            check(!failed && m.dirty,"temporary failure preserves the dirty draft")
            await m.retry()
            let remote=try await b.read("n1").text
            check(!m.dirty && NoteCodec.normalized(remote)=="Retry me","retry saves the preserved draft")
        } catch { fatalError("\(error)") }
        do {
            let (m,b,_)=await make()
            await b.blockNextRead()
            let poll=Task { await m.checkForExternalChanges() }
            await b.waitForRead()
            m.edited("Newer local save"); _ = await m.flush()
            await b.releaseRead(); await poll.value
            check(m.text=="Newer local save" && !m.dirty,"a delayed stale poll cannot roll back a newer save")
        }
        do {
            let (m,b,_)=await make()
            m.edited("Last keystroke before quit")
            let ok=await m.flush()
            let remote=try await b.read("n1").text
            check(ok && NoteCodec.normalized(remote)=="Last keystroke before quit","shutdown flush does not wait for debounce")
        } catch { fatalError("\(error)") }
        do {
            let (m,b,_)=await make()
            let before=m.text
            await b.canonicalizeHTML(); await m.checkForExternalChanges()
            check(m.text==before && !m.hasConflict,"HTML-only normalization does not replace editor text")
            await b.canonicalizeHTML()
            m.edited("New typing after HTML normalization")
            let ok=await m.flush()
            let remote=try await b.read("n1").text
            check(ok && !m.hasConflict && NoteCodec.normalized(remote)=="New typing after HTML normalization","serialization-only conflicts rebase once without losing edits")
        } catch { fatalError("\(error)") }
        do {
            let (m,b,_)=await make()
            m.notes=[NoteSummary(["id":"a","name":"가","modified":Date(timeIntervalSince1970:30),"created":Date(timeIntervalSince1970:10)]),NoteSummary(["id":"b","name":"나","modified":Date(timeIntervalSince1970:20),"created":Date(timeIntervalSince1970:40)])]
            m.settings.sortBy="created"; m.settings.sortAscending=false
            check(m.visibleNotes.map(\.id)==["b","a"],"created-date sort uses creation dates, not modification dates")
            m.notes[0].modified=Date(timeIntervalSince1970:500)
            check(m.visibleNotes.map(\.id)==["b","a"],"editing an older note does not move it ahead under creation-date order")
            m.settings.sortBy="title"; m.settings.sortAscending=true
            check(m.visibleNotes.map(\.id)==["a","b"],"title sort respects ascending order")
            m.previews["a"]="검색어"; m.search="검색어"; m.settings.searchScope="title"
            check(m.visibleNotes.isEmpty,"title-only search excludes preview matches")
            m.settings.searchScope="preview"
            check(m.visibleNotes.map(\.id)==["a"],"preview scope includes loaded body preview")
            m.search=""; m.settings.newNoteStyle="heading"
            m.folders.append(NoteFolder(["id":"f2","name":"별도 폴더","account":"iCloud"]))
            m.settings.defaultFolderID="f2"
            await m.newNote()
            check(await b.createdFolder=="f2" && m.selectedFolderID=="f2","new-note destination setting changes the actual backend folder")
            m.edited("새 머리말\n본문"); let okay=await m.flush()
            let saved=try await b.read("n3")
            check(okay && saved.html.contains("<h2>새 머리말</h2>"),"first autosave preserves configured heading after empty-note normalization")
            m.settings.reset()
        } catch {fatalError("\(error)")}
        do {
            let (m,_,_)=await make()
            var publications=0
            let observation=m.objectWillChange.sink {publications += 1}
            for i in 0..<100 {m.edited("연속 입력 \(i)")}
            check(publications==0,"100 keystrokes do not invalidate the SwiftUI note list or editor")
            check(m.text=="연속 입력 99" && m.dirty,"live text remains current without publishing each keystroke")
            _ = await m.flush(); observation.cancel()
        }
        do {
            let (m,b,_)=await make()
            await b.blockWrites(); m.edited("First background batch")
            let task=Task {await m.save()}; await b.waitForWrites(1)
            m.edited("Typing continues during background batch")
            await b.releaseWrites(); _ = await task.value
            check(await b.writeCount==1 && m.dirty,"background save writes one batch and defers newer typing")
            _ = await m.flush()
            check(await b.writeCount==2 && !m.dirty,"explicit flush drains the remaining batch")
        }
        do {
            let (m,b,_)=await make()
            let version=m.editorLoadVersion
            let doc=NoteDocument(paragraphs:[NoteParagraph(text:"첫 메모"),NoteParagraph(text:"본문",lists:[NoteList(id:1,kind:"decimal")])])
            m.editorBridge.noteID="n1"; m.editorBridge.loadVersion=m.editorLoadVersion; m.editorBridge.capture={doc}
            m.edited(m.text)
            check(m.dirty,"format-only list conversion marks the note dirty")
            let okay=await m.flush(); let saved=try await b.read("n1")
            check(okay && saved.html.contains("<ol>") && saved.document?.hasLists==true,"format-only changes save actual list structure")
            check(m.editorLoadVersion==version,"autosave does not reinstall or replace the live editor")
        } catch {fatalError("\(error)")}
        do {
            let (m,b,_)=await make()
            m.edited("작성 중인 본문"); let version=m.editorLoadVersion
            await b.addIncomingNote(); await m.refreshList()
            check(m.notes.contains{$0.id=="incoming"},"new native notes are discovered even while the selected note is dirty")
            check(m.text=="작성 중인 본문" && m.dirty && m.editorLoadVersion==version,"incoming note metadata never replaces in-progress typing")
            _ = await m.flush()
        }
        do {
            let (m,b,_)=await make()
            m.settings.autosaveMaxInterval=3
            for i in 0..<24 {m.edited("계속 입력 \(i)"); try await Task.sleep(nanoseconds:150_000_000)}
            check(await b.writeCount>=1,"continuous typing is periodically saved without waiting for idle")
            check(m.text=="계속 입력 23","periodic save preserves all later typing")
            _ = await m.flush(); m.settings.reset()
        } catch {fatalError("\(error)")}
        do {
            let (m,b,_)=await make()
            await b.blockWrites(); m.edited("automatic batch")
            let automatic=Task {await m.save()}; await b.waitForWrites(1)
            m.edited("final batch before quit")
            let quitFlush=Task {await m.flush()}; let navigationFlush=Task {await m.flush()}
            await b.releaseWrites(); _ = await automatic.value
            let quitOK=await quitFlush.value; let navigationOK=await navigationFlush.value
            check(quitOK && navigationOK && !m.dirty,"simultaneous quit/navigation flushes drain the active automatic writer")
            check(NoteCodec.normalized(try await b.read("n1").text)=="final batch before quit","concurrent flush completion never drops the final edit")
        } catch {fatalError("\(error)")}
        do {
            let (m,b,_)=await make()
            await b.delayReadback(2); m.edited("저장 확인이 늦어져도 전체 본문 유지")
            let okay=await m.flush()
            check(okay && !m.hasConflict && !m.dirty,"delayed own-write readback is confirmed without a false conflict")
            check(await b.writeCount==1,"waiting for readback never resubmits the body")
        }
        do {
            let (m,b,_)=await make()
            await b.failOnceAfterApplying(); m.edited("실제로 반영되었지만 응답이 지연된 본문")
            check(!(await m.flush()) && m.dirty,"uncertain write acknowledgement retains the draft")
            await m.retry()
            check(!m.hasConflict && !m.dirty,"retry recognizes that the requested document already reached Notes")
        }
        do {
            let (m,b,_)=await make()
            let first=try await b.read("n1")
            m.edited("첫 저장\n추가 문장"); _ = await m.flush()
            m.edited("첫 저장\n추가 문장\n작성 중인 마지막 문장")
            let load=m.editorLoadVersion
            await b.restore(first); await m.checkForExternalChanges()
            check(!m.hasConflict && m.text.hasSuffix("작성 중인 마지막 문장") && m.editorLoadVersion==load,"an exact older saved revision never replaces active typing")
            check(await m.flush(),"latest typing safely rebases on the exact known historical revision")
            let latest=try await b.read("n1")
            await b.restore(first); await m.checkForExternalChanges()
            check(m.text.hasSuffix("작성 중인 마지막 문장") && m.dirty && !m.hasConflict,"an older echo after a clean save keeps the acknowledged latest document")
            _ = await m.flush()
            check(try await b.read("n1").document!.equivalent(to:latest.document!),"the latest complete document is restored after an old echo")
            m.edited("새로 작성 중")
            await b.externalEdit(first.text); await m.checkForExternalChanges()
            check(m.hasConflict && m.text=="새로 작성 중","an intentional revert with a new timestamp is still treated as a real external edit")
        } catch {fatalError("\(error)")}
        do {
            let (m,b,_)=await make()
            let partial=NoteDocument(text:"일부 본문")
            m.editorBridge.noteID="n1"; m.editorBridge.loadVersion=m.editorLoadVersion
            m.editorBridge.capture={partial}; m.edited("전체 본문\n마지막 줄까지 유지")
            _ = await m.flush()
            check(NoteCodec.normalized(try await b.read("n1").text)==m.text,"a stale editor capture cannot replace newer model text with a partial body")
            let numbered=NoteDocument(paragraphs:[NoteParagraph(text:"동일한 글",lists:[NoteList(id:1,kind:"decimal")])])
            m.editorBridge.loadVersion=m.editorLoadVersion &- 1; m.editorBridge.capture={numbered}; m.edited("동일한 글")
            _ = await m.flush()
            check(try await b.read("n1").document?.hasLists==false,"a previous editor installation cannot leak its formatting into the active note")
        } catch {fatalError("\(error)")}
        do {
            let (m,b,url)=await make()
            let old=try await b.read("n1")
            m.edited("재실행 후에도 유지할 전체 작성본"); _ = await m.flush()
            await b.restore(old)
            let restarted=NotesModel(backend:b,supportURL:url,startTimer:false,debounceNanoseconds:60_000_000_000)
            await restarted.connect(); await restarted.chooseNote("n1")
            check(restarted.text==m.text && restarted.dirty && !restarted.hasConflict,"durable revision history protects an acknowledged edit across relaunch")
            _ = await restarted.flush()
        } catch {fatalError("\(error)")}
        do {
            let (m,b,url)=await make()
            m.edited("복구할 로컬 초안"); m.persistDraft()
            await b.failOnce(); _ = await m.flush()
            await b.canonicalizeHTML()
            let restarted=NotesModel(backend:b,supportURL:url,startTimer:false,debounceNanoseconds:60_000_000_000)
            await restarted.connect(); await restarted.chooseNote("n1")
            check(restarted.text=="복구할 로컬 초안" && restarted.dirty && !restarted.hasConflict,"draft recovery tolerates canonical HTML changes to the original base")
            _ = await restarted.flush()
        }
        do {
            let (m,b,url)=await make()
            m.edited("서식을 바꿀 본문"); _ = await m.flush()
            let doc=NoteDocument(paragraphs:[NoteParagraph(text:m.text,lists:[NoteList(id:1,kind:"decimal")])])
            m.editorBridge.noteID="n1"; m.editorBridge.loadVersion=m.editorLoadVersion; m.editorBridge.capture={doc}
            m.edited(m.text); m.persistDraft(); await b.failOnce(); _ = await m.flush()
            let restarted=NotesModel(backend:b,supportURL:url,startTimer:false,debounceNanoseconds:60_000_000_000)
            await restarted.connect(); await restarted.chooseNote("n1")
            check(restarted.dirty && restarted.editorDocument?.hasLists==true,"format-only drafts survive relaunch even when their text matches the remote note")
            _ = await restarted.flush()
        }
        do {
            let (m,b,url)=await make()
            m.edited("현재 Mac에서 작성한 전체 문장"); await b.externalEdit("iPhone에서 수정한 문장")
            await m.checkForExternalChanges()
            let reviewed=await m.reviewConflict()
            check(reviewed?.text=="iPhone에서 수정한 문장" && m.text=="현재 Mac에서 작성한 전체 문장","conflict review exposes both versions without replacing the local editor")
            await m.openOriginal()
            check(await b.showCount==0,"opening Apple Notes cannot silently display an older version while local saving is blocked")
            await b.externalEdit("확인하는 동안 다시 변경됨")
            check(!(await m.resolveConflict(usingLocal:true,reviewed:reviewed!)) && m.hasConflict,"resolution refuses to overwrite a remote edit made after review")
            let latest=await m.reviewConflict()
            check(await m.resolveConflict(usingLocal:true,reviewed:latest!),"explicitly choosing the local version saves through normal conflict-checked autosave")
            check(NoteCodec.normalized(try await b.read("n1").text)=="현재 Mac에서 작성한 전체 문장","local resolution stores the complete current document")
            let recovered=try FileManager.default.contentsOfDirectory(at:url.appendingPathComponent("Recovered"),includingPropertiesForKeys:nil)
            let files=try FileManager.default.contentsOfDirectory(atPath:recovered[0].path)
            check(files.contains("NotesPlus.json") && files.contains("AppleNotes.json"),"both reviewed versions are durably archived before conflict resolution")
            m.edited("두 번째 로컬 초안"); await b.externalEdit("선택할 기기 버전"); await m.checkForExternalChanges()
            let remote=await m.reviewConflict()
            check(await m.resolveConflict(usingLocal:false,reviewed:remote!),"the user can choose the reviewed remote version")
            check(m.text=="선택할 기기 버전" && !m.dirty && !m.hasConflict,"remote resolution installs only the reviewed document and clears the active draft")
        } catch {fatalError("\(error)")}
        do {
            let (m,b,url)=await make()
            let old=try await b.read("n1")
            m.edited("최근 저장본"); _ = await m.flush()
            m.edited("아직 동기화하지 못한 최신 초안"); await b.failOnce(); _ = await m.flush()
            await b.restore(old)
            let restarted=NotesModel(backend:b,supportURL:url,startTimer:false,debounceNanoseconds:60_000_000_000)
            await restarted.connect(); await restarted.chooseNote("n1")
            let reviewed=await restarted.reviewConflict()
            check(reviewed != nil && restarted.hasConflict,"a recovered draft conflicting with an older remote version remains reviewable")
            check(await restarted.resolveConflict(usingLocal:false,reviewed:reviewed!),"the user can explicitly keep an older remote version")
            let again=NotesModel(backend:b,supportURL:url,startTimer:false,debounceNanoseconds:60_000_000_000)
            await again.connect(); await again.chooseNote("n1")
            check(again.text==old.document?.text && !again.dirty,"relaunch honors an explicit remote choice instead of resurrecting archived local history")
        } catch {fatalError("\(error)")}
        do {
            let (m,b,url)=await make()
            let full="부분 저장 복구\n전체 문장\n마지막 줄까지 남아 있어야 합니다"
            m.edited(full); await b.failOnce(); _ = await m.flush()
            let file=try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).first{$0.lastPathComponent.hasPrefix("draft-")}!
            var legacy=try JSONDecoder().decode(LocalDraft.self,from:Data(contentsOf:file))
            legacy.document=NoteDocument(text:"부분 저장 복구")
            legacy.baseDocument=nil
            try JSONEncoder().encode(legacy).write(to:file,options:.atomic)
            let restarted=NotesModel(backend:b,supportURL:url,startTimer:false,debounceNanoseconds:60_000_000_000)
            await restarted.connect(); await restarted.chooseNote("n1")
            check(restarted.text==full && restarted.editorDocument?.text==full,"legacy partial rich-text captures never hide the complete saved draft after upgrade")
            _ = await restarted.flush()
            check(NoteCodec.normalized(try await b.read("n1").text)==full,"upgraded legacy drafts save the complete recovered body")
        } catch {fatalError("\(error)")}
        do {
            let (m,b,url)=await make()
            m.edited("업데이트 종료 전 반드시 보관할 초안"); await b.failOnce(); _ = await m.flush()
            let file=try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).first{$0.lastPathComponent.hasPrefix("draft-")}!
            try FileManager.default.removeItem(at:file)
            try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
            var failed=false
            do {try await m.preserveUnsavedDraft()} catch {failed=true}
            check(failed && m.dirty,"a local draft write failure prevents claiming a safe update shutdown")
            try FileManager.default.removeItem(at:file)
            try await m.preserveUnsavedDraft()
            let restored=try JSONDecoder().decode(LocalDraft.self,from:Data(contentsOf:file))
            check(restored.text==m.text,"update shutdown waits for the complete draft to reach disk")
        } catch {fatalError("\(error)")}
        for url in directories { try? FileManager.default.removeItem(at:url) }
        print("\(checks) autosave checks passed.")
    }
}
