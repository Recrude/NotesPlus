import AppKit

actor DelayedCloud:CloudRequesting {
    var remote:CloudSnapshot
    var fail=false
    var saves=0
    init(_ remote:CloudSnapshot){self.remote=remote}
    func setRemote(_ value:CloudSnapshot){remote=value}
    func setFailure(_ value:Bool){fail=value}
    func request<T:Decodable & Sendable>(_ command:String,account:CloudAccount?,payload:[String:Any],as:T.Type)async throws->T {
        if command=="save" {
            let sent=try JSONDecoder().decode(CloudDocument.self,from:JSONSerialization.data(withJSONObject:payload["document"]!))
            try await Task.sleep(for:.milliseconds(120))
            if fail {throw CloudFailure(code:"CONFLICT",message:"동시 편집 충돌")}
            saves+=1;remote.document=sent;remote.tag="saved-\(saves)"
        }
        return try JSONDecoder().decode(T.self,from:JSONEncoder().encode(remote))
    }
}
@main struct StructuredSyncTests {
    @MainActor static func main() async throws {
        let base=CloudSnapshot(id:"sync-fixture",title:"Test",tag:"base",document:CloudDocument(paragraphs:[CloudParagraph(text:"원본")]),created:0)
        let backend=DelayedCloud(base)
        let account=CloudAccount(session:CloudSession(cookie:"fixture",clientId:"fixture",clientBuildNumber:"fixture",clientMasteringNumber:"fixture",capturedAt:"fixture"),dsid:"fixture",host:"fixture")
        let support=FileManager.default.temporaryDirectory.appendingPathComponent("notesplus-sync-\(UUID().uuidString)")
        defer{try? FileManager.default.removeItem(at:support)}
        let model=StructuredModel(client:backend,account:account,startTasks:false,support:support)
        model.snapshot=base;model.document=base.document
        let first=CloudDocument(paragraphs:[CloudParagraph(text:"첫 저장 중")]),latest=CloudDocument(paragraphs:[CloudParagraph(text:"첫 저장 중에도 계속 입력한 전체 본문 😀")])
        model.edited(first)
        let save=Task{await model.save()}
        try await Task.sleep(for:.milliseconds(30));model.edited(latest);await save.value
        precondition(model.document==latest && model.dirty,"In-flight response must not replace newer typing")
        precondition(model.snapshot!.document==first,"Next save must rebase from submitted content")
        await model.save();precondition(!model.dirty && model.document==latest,"Latest full document committed")
        let committed=model.snapshot!
        await backend.setRemote(base);await model.refresh()
        precondition(model.document==latest,"Old readback must not replace an acknowledged save")
        var phone=committed;phone.tag="phone-1";phone.document.paragraphs.append(CloudParagraph(text:"iPhone에서 추가"))
        await backend.setRemote(phone);await model.refresh();precondition(model.document==phone.document,"New remote edit installs while idle")
        var continued=phone.document;continued.paragraphs.append(CloudParagraph(text:"NotesPlus에서 이어서 입력"));model.edited(continued)
        await backend.setFailure(true);await model.save()
        precondition(model.dirty && model.document==continued,"Conflict must retain editable complete draft")
        let draft=try Data(contentsOf:support.appendingPathComponent("sync-fixture.json"))
        let raw=try JSONSerialization.jsonObject(with:draft) as! [String:Any]
        let stored=try JSONDecoder().decode(CloudDocument.self,from:JSONSerialization.data(withJSONObject:raw["document"]!))
        precondition(stored==continued,"Full structured draft survives conflict on disk")
        let restored=StructuredModel(client:backend,account:account,startTasks:false,support:support)
        await restored.select("sync-fixture")
        precondition(restored.dirty && restored.document==continued,"Restart restores complete conflicted draft")
        await backend.setFailure(false);await model.save()
        precondition(!model.dirty,"Editing remains saveable after retry")
        await backend.setRemote(base)
        let reopened=StructuredModel(client:backend,account:account,startTasks:false,support:support)
        await reopened.select("sync-fixture")
        precondition(reopened.document==continued && !reopened.dirty,"Persisted history rejects stale read after restart")
        print("PASS: in-flight typing, acknowledged-save echo rejection, iPhone edit return, conflict draft, retry")
    }
}
