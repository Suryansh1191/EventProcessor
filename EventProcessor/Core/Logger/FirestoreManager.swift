import Foundation
import FirebaseFirestore

final class FirestoreManager: LogUploaderProtocol {
    private let db = Firestore.firestore()
    private let collectionName = "logs_by_minute"
    
    /// Formatter to ensure consistency in document naming or grouping
    private let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    func upload(events: [LogMinEntry]) async throws {
        // Firestore batches are limited to 500 operations.
        let chunks = events.chunked(into: 500)
        
        for chunk in chunks {
            let batch = db.batch()
            
            for entry in chunk {
                // Truncate the date to the minute for the document metadata
                let minuteId = minuteFormatter.string(from: entry.timestamp)
                let docRef = db.collection(collectionName).document(minuteId)
                
                let logData = entry.logs.map { log in
                    [
                        "value": log.value,
                        "timestamp": Timestamp(date: log.timestamp)
                    ]
                }
                
                let data: [String: Any] = [
                    "timestamp": Timestamp(date: entry.timestamp),
                    "metaString": entry.metaString,
                    "logs": logData
                ]
                
                batch.setData(data, forDocument: docRef, merge: true)
            }
            
            try await batch.commit()
        }
    }
}

// Helper for Batching
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
