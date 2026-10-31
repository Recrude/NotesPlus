import Foundation

struct SyncRevision:Codable,Sendable {
    var html:String
    var text:String
    var document:NoteDocument?
    var modified:Date
    var recorded:Date
    init(_ note:NoteSnapshot) {
        html=note.html; text=note.text; document=note.document; modified=note.modified; recorded=Date()
    }
}

struct SyncHistory:Codable,Sendable {
    var id:String
    var revisions:[SyncRevision]=[]
    mutating func remember(_ note:NoteSnapshot) {
        guard note.profile.editable else{return}
        if let last=revisions.last,last.html==note.html,last.modified==note.modified {return}
        revisions.append(SyncRevision(note))
        while revisions.count>8 {revisions.removeFirst()}
        while revisions.count>2,revisions.reduce(0,{$0+$1.html.utf8.count})>2_000_000 {revisions.removeFirst()}
    }
    func contains(_ note:NoteSnapshot)->Bool {
        revisions.contains { revision in
            // Matching text alone could also be an intentional revert from another device.
            revision.modified==note.modified && (revision.html==note.html || (revision.document != nil && note.document != nil && revision.document!.equivalent(to:note.document!)))
        }
    }
}
