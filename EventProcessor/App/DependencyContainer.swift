import Foundation

final class DependencyContainer {
    let database: LogDBProtocol
    let uploader: LogUploaderProtocol
    let syncManager: LogSyncManager

    init() {
        self.database = LogSQLite()
        self.uploader = FirestoreManager()
        
        self.syncManager = LogSyncManager(
            database: database,
            uploader: uploader
        )
        self.syncManager.start()
    }
}
