import Foundation

struct LogEntry: Codable {
    let value: Int
    let timestamp: Date
}

/// Represents the aggregated minute container
struct LogMinEntry: Codable {
    let timestamp: Date
    var metaString: String
    var logs: [LogEntry]
}
