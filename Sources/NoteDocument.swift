import Foundation

struct NoteList: Codable, Equatable, Sendable {
    var id:Int
    var kind:String // decimal, disc, circle, dash
    var start:Int = 1
    var ordered:Bool {kind=="decimal"}
}
struct NoteParagraph: Codable, Equatable, Sendable {
    var text:String
    var lists:[NoteList] = []
}
struct NoteDocument: Codable, Equatable, Sendable {
    var paragraphs:[NoteParagraph]
    init(text:String) {
        paragraphs=text.replacingOccurrences(of:"\r\n",with:"\n").components(separatedBy:"\n").map{NoteParagraph(text:$0)}
    }
    init(paragraphs:[NoteParagraph]) {self.paragraphs=paragraphs.isEmpty ? [NoteParagraph(text:"")] : paragraphs}
    var text:String {paragraphs.map(\.text).joined(separator:"\n")}
    var hasLists:Bool {paragraphs.contains{!$0.lists.isEmpty}}
    var canonical:NoteDocument {
        var result=paragraphs
        while result.count>1, let p=result.last, p.text.isEmpty, p.lists.isEmpty {result.removeLast()}
        // IDs identify boundaries, not persistent identifiers. Canonicalize by first occurrence.
        var ids:[Int:Int]=[:]
        for i in result.indices {
            result[i].text=result[i].text.replacingOccurrences(of:"\u{00a0}",with:" ")
            result[i].lists=result[i].lists.map {list in
                var copy=list
                if ids[list.id]==nil {ids[list.id]=ids.count+1}
                copy.id=ids[list.id]!; return copy
            }
        }
        return NoteDocument(paragraphs:result)
    }
    func equivalent(to other:NoteDocument)->Bool {canonical==other.canonical}
}
