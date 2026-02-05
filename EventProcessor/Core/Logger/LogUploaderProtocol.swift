import Foundation

protocol LogUploaderProtocol {
    
    /// Uploads an array of log entries to a remote destination.
    func upload(events: [LogMinEntry]) async throws
}
