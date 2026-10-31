import Foundation

protocol NotesBackend: Sendable {
    func folders() async throws -> [NoteFolder]
    func notes(in folder: String) async throws -> [NoteSummary]
    func read(_ id: String) async throws -> NoteSnapshot
    func create(in folder: String, html: String) async throws -> NoteSnapshot
    func write(_ id: String, expectedHTML: String, html: String) async throws -> NoteSnapshot
    func show(_ id: String) async throws
}

final class NotesService: NotesBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.notesplus.notes-bridge", qos: .userInitiated)
    private let store = NPNotesStore()
    private func perform<T>(_ operation: @escaping (NPNotesStore) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { autoreleasepool {
                do { continuation.resume(returning: try operation(self.store)) }
                catch { continuation.resume(throwing: error) }
            } }
        }
    }
    func folders() async throws -> [NoteFolder] {
        try await perform { try $0.folders().map { NoteFolder($0 as? [String:Any] ?? [:]) } }
    }
    func notes(in folder:String) async throws -> [NoteSummary] {
        try await perform { try $0.notes(inFolder:folder).map { NoteSummary($0 as? [String:Any] ?? [:]) } }
    }
    func read(_ id:String) async throws -> NoteSnapshot {
        try await perform { store in
            for _ in 0..<3 {
                let value=NoteSnapshot(try store.readNote(id) as? [String:Any] ?? [:])
                if !value.inconsistentBody {return value}
            }
            throw Self.unstableRead()
        }
    }
    func create(in folder:String,html:String) async throws -> NoteSnapshot {
        try await perform { NoteSnapshot(try $0.createNote(inFolder:folder,html:html) as? [String:Any] ?? [:]) }
    }
    func write(_ id:String,expectedHTML:String,html:String) async throws -> NoteSnapshot {
        try await perform {
            let value=NoteSnapshot(try $0.saveNote(id,expectedHTML:expectedHTML,html:html) as? [String:Any] ?? [:])
            guard !value.inconsistentBody else {throw Self.unstableRead()}
            return value
        }
    }
    func show(_ id:String) async throws {
        _ = try await perform { try $0.showNote(id) }
    }
    private static func unstableRead()->NSError {
        NSError(domain:"NotesPlus",code:425,userInfo:[NSLocalizedDescriptionKey:"메모 본문과 서식의 동기화가 진행 중입니다. 작성 내용을 유지하고 다시 확인합니다."])
    }
}
