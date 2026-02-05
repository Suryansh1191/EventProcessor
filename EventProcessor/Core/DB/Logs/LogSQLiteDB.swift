import Foundation
import SQLite

// MARK: - Database Class
class LogSQLite {
    
    private var db: Connection?
    private let queue = DispatchQueue(label: "com.app.dbQueue", qos: .userInitiated)
    
    // MARK: - Table Definitions
    private let minutesTable = Table("minutes_table")
    private let id = Expression<Int64>("id")
    private let minuteStart = Expression<Date>("minute_start")
    private let metaData = Expression<String?>("meta_data")
    
    private let secondsTable = Table("seconds_table")
    private let secValue = Expression<Int>("sec_value")
    private let secTime = Expression<Date>("sec_time")
    private let minuteIdFK = Expression<Int64>("minute_id")

    // MARK: - Initialization
    init(path: String? = nil) {
        do {
            let dbPath = path ?? "\(NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)/app_logs.sqlite3"
            self.db = try Connection(dbPath)
            try createTables()
        } catch {
            print("CRITICAL DB ERROR: \(error)") // Don't crash, just log.
            self.db = nil
        }
    }
    
    private func createTables() throws {
        guard let db = db else { return }
        
        try db.run(minutesTable.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(minuteStart, unique: true)
            t.column(metaData)
        })
        
        try db.run(secondsTable.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(minuteIdFK, references: minutesTable, id)
            t.column(secValue)
            t.column(secTime)
        })
    }
    
    private func getStartOfMinute(from date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }
}

extension LogSQLite: LogDBProtocol {
        
    func addEvent(data: Int, timestamp: Date) throws {
        guard let db = db else { return }
        // Run synchronously on our custom queue to prevent data races
        try queue.sync {
            let minDate = getStartOfMinute(from: timestamp)
            var parentId: Int64 = 0
            
            // 1. Get or Create Minute Container
            if let existingMinute = try db.pluck(minutesTable.filter(minuteStart == minDate)) {
                parentId = existingMinute[id]
            } else {
                parentId = try db.run(minutesTable.insert(
                    minuteStart <- minDate,
                    metaData <- ""
                ))
            }
            
            // 2. Insert Second Log
            try db.run(secondsTable.insert(
                minuteIdFK <- parentId,
                secValue <- data,
                secTime <- timestamp
            ))
        }
    }
    
    func update(metadataWith entries: [Date: String]) throws {
        guard let db = db else { return }
        
        try queue.sync {
            try db.transaction {
                for (timestamp, meta) in entries {
                    let minDate = getStartOfMinute(from: timestamp)
                    let query = minutesTable.filter(minuteStart == minDate)
                    
                    // Attempt to update existing record
                    if try db.run(query.update(self.metaData <- meta)) == 0 {
                        try db.run(minutesTable.insert(
                            minuteStart <- minDate,
                            self.metaData <- meta
                        ))
                    }
                }
            }
        }
    }
    
    func getEvents(startTime: Date, endTime: Date) async throws -> [LogMinEntry] {
        // Run on background thread to avoid blocking UI
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(returning: [])
                    return
                }
                
                do {
                    let query = self.minutesTable.filter(self.minuteStart >= startTime && self.minuteStart <= endTime)
                                            .order(self.minuteStart.asc)
                    
                    var results: [LogMinEntry] = []
                    let rows = try db.prepare(query)
                    
                    for row in rows {
                        let parentId = row[self.id]
                        let mStart = row[self.minuteStart]
                        let mString = row[self.metaData] ?? ""
                        
                        // Fetch Children
                        let secondsQuery = self.secondsTable.filter(self.minuteIdFK == parentId).order(self.secTime.asc)
                        let secRows = try db.prepare(secondsQuery)
                        let secondLogs = secRows.map { LogEntry(value: $0[self.secValue], timestamp: $0[self.secTime]) }
                        
                        results.append(LogMinEntry(
                            timestamp: mStart,
                            metaString: mString,
                            logs: secondLogs
                        ))
                    }
                    continuation.resume(returning: results)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    func addEvents(events: [LogMinEntry]) throws {
        guard let db = db else { return }
        
        // 1. Enter the serial queue to ensure thread safety
        try queue.sync {
            
            // Start a Transaction.
            try db.transaction {
                for entry in events {
                    
                    // Ensure the date is normalized to the start of the minute
                    // (Just in case the LogMinEntry timestamp has seconds/milliseconds)
                    let minDate = self.getStartOfMinute(from: entry.timestamp)
                    var parentId: Int64 = 0
                    
                    // Upsert Logic for Minute Container
                    let minuteQuery = self.minutesTable.filter(self.minuteStart == minDate)
                    
                    if let existingMinute = try db.pluck(minuteQuery) {
                        parentId = existingMinute[self.id]
                        
                        // Optional: If the new entry has metadata, update the existing record.
                        // If you prefer to keep old metadata, remove this block.
                        if !entry.metaString.isEmpty {
                            try db.run(minuteQuery.update(self.metaData <- entry.metaString))
                        }
                    } else {
                        // Create new minute container
                        parentId = try db.run(self.minutesTable.insert(
                            self.minuteStart <- minDate,
                            self.metaData <- entry.metaString
                        ))
                    }
                    
                    // Insert all Logs for this Minute
                    for log in entry.logs {
                        try db.run(self.secondsTable.insert(
                            self.minuteIdFK <- parentId,
                            self.secValue <- log.value,
                            self.secTime <- log.timestamp
                        ))
                    }
                }
            }
        }
    }
    
}
