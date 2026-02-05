import Foundation
import Combine

class HomeViewModel: ObservableObject {
    
    @Published var resentEvent: LogEntry?
    @Published var resentLLMOutput: String = "Waiting for the first request..."
    @Published var processingLogs = false
    private var logService: LogDBService
    private var llmRunner: LLMInferenceProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    init(
        logService: LogDBService = LogDBService(),
        llmRunner: LLMInferenceProtocol = LlamaCppRunner()
    ) {
        self.logService = logService
        self.llmRunner = llmRunner
        
        //loading model if not loaded
        loadLLMModel()
    }
    
    func startService() {
        
        // Fires every second
        let sharedTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .map { [weak self] _ in
                let log = self?.getLog()
                if let log { Task.detached { await self?.sendLog(log: log) } }
                return log
            }
            .compactMap { $0 }
            .share()
        
        // Update UI
        sharedTimer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entry in
                self?.resentEvent = entry
            }
            .store(in: &cancellables)
        
        
        // Processing in every 60 seconds
        sharedTimer
            .collect(.byTime(DispatchQueue.global(qos: .utility), 10.0))
            .sink { [weak self] logs in
                Task {
                    await self?.processBatch(logs)
                }
            }
            .store(in: &cancellables)
    }
    
    func stopService() {
        cancellables.removeAll()
    }
    
    private func sendLog(log: LogEntry) {
        logService.log(value: log)
    }
    
    private func sendMetaString(string: String, for date: Date) {
        logService.update(metaString: string, for: date)
    }
    
    private func processBatch(_ logs: [LogEntry]) async {
        guard !logs.isEmpty else { return }
        let randomLog = logs.randomElement()!
        
        await MainActor.run {
            processingLogs = true
        }
        
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            let processText = await self.process(randomLog)
            debugPrint("Process output text from LLM: \(processText)")
            
            await MainActor.run {
                self.resentLLMOutput = processText
                self.processingLogs = true
                self.sendMetaString(
                    string: processText,
                    for: randomLog.timestamp
                )
            }
        }
    }
    
    private func getLog() -> LogEntry {
        return LogEntry(value: Int.random(in: 1...100), timestamp: Date())
    }
}


//MARK: LLM Work
extension HomeViewModel {
    
    func loadLLMModel() {
        Task.detached { [weak self] in
            guard let self else { return }
            if await self.llmRunner.isLoaded { return }
            do {
                if let modelPath = await Bundle.main.path(
                    forResource: SystemConstants.llmModel,
                    ofType: SystemConstants.modelExtension
                ) {
                    try await self.llmRunner.loadModel(path: modelPath)
                }
            } catch {
                print("Load Model error: \(error.localizedDescription)")
            }
        }
    }
    
    func process(_ log: LogEntry) async -> String {
        let maxRetries: Int = 3
        var tryCount: Int = 0
        
        //Retry logic
        while tryCount < maxRetries {
            tryCount += 1
            
            switch await callLLM(for: log) {
            case .success(let text):
                return text
            case .failure(let error):
                debugPrint("-> Generation failed with error: \(error)")
                debugPrint("-> Retrying LLM Generation...")
                continue
            }
        }
        
        return "LLM generation Failed after retries..."
    }
    
    func callLLM(for log: LogEntry) async -> Result<String, Error> {
        var generatedText = ""
        
        do {
            for try await token in self.llmRunner.generate(
                with: SystemConstants.defaultPrompt + "\(log.value)"
            ) {
                generatedText += token
            }
            
            return .success(generatedText)
        } catch {
            return .failure(error)
        }
    }
}
