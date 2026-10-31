import Foundation

final class DraftWriter:@unchecked Sendable {
    private let queue=DispatchQueue(label:"dev.notesplus.drafts",qos:.utility)
    func submit(_ draft:LocalDraft?,to url:URL,onError:@escaping @Sendable (Error)->Void) {
        queue.async {
            do {if let draft {try Self.write(draft,to:url)} else if FileManager.default.fileExists(atPath:url.path) {try FileManager.default.removeItem(at:url)}}
            catch {onError(error)}
        }
    }
    func backup(_ draft:LocalDraft,to url:URL) async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            queue.async {do {try Self.write(draft,to:url); continuation.resume()} catch {continuation.resume(throwing:error)}}
        }
    }
    func barrier() async {await withCheckedContinuation {continuation in queue.async {continuation.resume()}}}
    private static func write(_ draft:LocalDraft,to url:URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(draft).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}
