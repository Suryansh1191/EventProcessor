import Foundation

protocol LogDBProtocol {
    /// Adds a single log entry. Automatically creates the minute container if missing.
    func addEvent(data: Int, timestamp: Date) throws
    
    /// Bulk adds multiple minute entries and their associated logs in a single transaction.
    func addEvents(events: [LogMinEntry]) throws 
    
    /// Updates the metadata string for the minute containing the given timestamp.
    func update(metadataWith entries: [Date: String]) throws
    
    /// Retrieves logs grouped by minute within the specified range.
    func getEvents(startTime: Date, endTime: Date) async throws -> [LogMinEntry]
}
