import Foundation

final class LogSyncManager {
    private let database: LogDBProtocol
    private let uploader: LogUploaderProtocol
    private let syncInterval: TimeInterval = 300 // 5 Minutes
    
    private var timer: Timer?
    private var isSyncing = false
    private let lastSyncKey = "com.app.lastSyncTimestamp"
    private var lastSyncDate: Date {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date ?? Date() }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    init(database: LogDBProtocol, uploader: LogUploaderProtocol) {
        self.database = database
        self.uploader = uploader
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { try? await self?.sync() }
        }
    }

    private func sync() async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let startTime = lastSyncDate
        let endTime = Date()

        let events = try await database.getEvents(startTime: startTime, endTime: endTime)
        
        if !events.isEmpty {
            try await uploader.upload(events: events)
        }
        
        // Only update the timestamp if the upload succeeds
        lastSyncDate = endTime
    }
}
