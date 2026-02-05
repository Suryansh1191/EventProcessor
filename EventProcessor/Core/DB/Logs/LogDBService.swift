import Foundation
import AppKit

class LogDBService {
    
    // MARK: - Dependencies
    private let db: LogDBProtocol
    private let flushInterval: TimeInterval
    
    // MARK: - State
    private let queue = DispatchQueue(label: "com.app.logService", attributes: .concurrent)
    private var buffer: [TimeInterval: LogMinEntry] = [:]
    private var metaStringBuffer: [Date: String] = [:]
    private var timer: DispatchSourceTimer?
    
    init(db: LogDBProtocol = LogSQLite(), flushIntervalMinutes: Int = 2) {
        self.db = db
        self.flushInterval = TimeInterval(flushIntervalMinutes * 60)
        
        startTimer()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopTimer()
        forceFlush()
    }
    
    // MARK: - Public API
    
    /// Thread-safe logging. Groups into LogMinEntry immediately in memory.
    func log(value: LogEntry) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Calculate the start of the minute (the Key)
            let rawTime = value.timestamp.timeIntervalSince1970
            let minuteStart = rawTime - rawTime.truncatingRemainder(dividingBy: 60)
            
            // Check if a group exists for this minute
            if self.buffer[minuteStart] != nil {
                self.buffer[minuteStart]?.logs.append(value)
            } else {
                let newGroup = LogMinEntry(
                    timestamp: Date(timeIntervalSince1970: minuteStart),
                    metaString: "",
                    logs: [value]
                )
                self.buffer[minuteStart] = newGroup
            }
        }
    }
    
    func update(metaString: String, for timeStamp: Date ) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Calculate the start of the minute (the Key)
            let rawTime = timeStamp.timeIntervalSince1970
            let minuteStart = rawTime - rawTime.truncatingRemainder(dividingBy: 60)
            
            if self.buffer[minuteStart] != nil {
                self.buffer[minuteStart]?.metaString = metaString
            } else {
                self.metaStringBuffer[timeStamp] = metaString
            }
            
        }
    }
    
    /// Manually force a flush (useful for debugging or logout)
    func forceFlush() {
        flushToDB()
    }
    
    // MARK: - Internal Logic
    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        
        timer.setEventHandler { [weak self] in
            self?.flushToDB()
        }
        
        timer.resume()
        self.timer = timer
    }
    
    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
    
    private func flushToDB() {
        var batchToProcess: [LogMinEntry] = []
        var metaStringToFlush: [Date: String] = [:]
        
        queue.sync(flags: .barrier) {
            if !self.buffer.isEmpty {
                batchToProcess = Array(self.buffer.values)
                self.buffer.removeAll(keepingCapacity: true)
            }
            
            if !self.metaStringBuffer.isEmpty {
                metaStringToFlush = self.metaStringBuffer
                self.metaStringBuffer.removeAll(keepingCapacity: true)
            }
        }
        
        // If nothing to write, exit
        guard !batchToProcess.isEmpty else { return }
        
        // Process data in background
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            
            do {
                // if any existing metaString to push
                if !metaStringToFlush.isEmpty {
                    debugPrint("Updating metadata in the DB...")
                    try await self.db.update(metadataWith: metaStringToFlush)
                }
                
                debugPrint("LogService: Flushing \(batchToProcess.count) logs...")
                try await self.db.addEvents(events: batchToProcess)
            } catch {
                debugPrint("-> Error: Failed to flush logs to DB: \(error.localizedDescription)")
                //TODO: Handle This
            }
        }
    }
}

//MARK: For App termination
extension LogDBService {
    
    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc
    private func appWillTerminate() {
        debugPrint("LogService: App will terminate — flushing logs")
        stopTimer()
        forceFlushSync()
    }
    
    private func forceFlushSync() {
        var batchToProcess: [LogMinEntry] = []
        var metaStringToFlush: [Date: String] = [:]

        queue.sync(flags: .barrier) {
            batchToProcess = Array(self.buffer.values)
            self.buffer.removeAll()

            metaStringToFlush = self.metaStringBuffer
            self.metaStringBuffer.removeAll()
        }

        guard !batchToProcess.isEmpty else { return }

        let semaphore = DispatchSemaphore(value: 0)

        Task.detached(priority: .utility) { [weak self] in
            defer { semaphore.signal() }
            guard let self else { return }

            if !metaStringToFlush.isEmpty {
                try? await self.db.update(metadataWith: metaStringToFlush)
            }

            try? await self.db.addEvents(events: batchToProcess)
        }

        // ⛔️ Block briefly to ensure write completes
        _ = semaphore.wait(timeout: .now() + 3)
    }

}
