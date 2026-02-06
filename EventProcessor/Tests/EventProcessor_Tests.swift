import Foundation
import XCTest
import Combine
@testable import EventProcessor

final class HomeViewModelTests: XCTestCase {
    
    // MARK: - Test Doubles
    
    /// In-memory DB that satisfies `LogDBProtocol` without touching SQLite.
    final class DummyLogDB: LogDBProtocol {
        func addEvent(data: Int, timestamp: Date) throws {}
        func addEvents(events: [LogMinEntry]) throws {}
        func update(metadataWith entries: [Date : String]) throws {}
        func getEvents(startTime: Date, endTime: Date) async throws -> [LogMinEntry] { [] }
    }
    
    class MockLLMRunner: LLMInferenceProtocol {
        var isLoaded: Bool = false
        var tokensToEmit: [String] = []
        var shouldThrow: Bool = false
        private(set) var receivedPrompts: [String] = []
        
        func loadModel(path: String, contextSize: UInt32) throws {
            isLoaded = true
        }
        
        func loadModel(path: String) throws {
            isLoaded = true
        }
        
        func offloadModel() {
            isLoaded = false
        }
        
        func generate(with prompt: String, maxTokens: Int32) -> AsyncThrowingStream<String, Error> {
            receivedPrompts.append(prompt)
            
            if shouldThrow {
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: NSError(domain: "MockLLM", code: -1))
                }
            }
            
            let tokens = tokensToEmit
            return AsyncThrowingStream { continuation in
                Task {
                    for token in tokens {
                        continuation.yield(token)
                    }
                    continuation.finish()
                }
            }
        }
        
        func generate(with prompt: String) -> AsyncThrowingStream<String, Error> {
            generate(with: prompt, maxTokens: 128)
        }
    }
    
    // MARK: - Tests for callLLM
    
    func test_callLLM_successConcatenatesTokens() async throws {
        let mockLogService = LogDBService(db: DummyLogDB())
        let mockLLM = MockLLMRunner()
        mockLLM.tokensToEmit = ["Hello", " ", "World"]
        
        let viewModel = HomeViewModel(logService: mockLogService, llmRunner: mockLLM)
        let log = LogEntry(value: 42, timestamp: Date())
        
        let result = await viewModel.callLLM(for: log)
        
        switch result {
        case .success(let text):
            XCTAssertEqual(text, "Hello World")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
        
        XCTAssertEqual(mockLLM.receivedPrompts.count, 1)
        XCTAssertTrue(mockLLM.receivedPrompts.first?.contains("\(log.value)") ?? false)
    }
    
    func test_callLLM_failurePropagatesError() async {
        let mockLogService = LogDBService(db: DummyLogDB())
        let mockLLM = MockLLMRunner()
        mockLLM.shouldThrow = true
        
        let viewModel = HomeViewModel(logService: mockLogService, llmRunner: mockLLM)
        let log = LogEntry(value: 1, timestamp: Date())
        
        let result = await viewModel.callLLM(for: log)
        
        switch result {
        case .success:
            XCTFail("Expected failure when LLM throws")
        case .failure:
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - Tests for process(retry logic)
    
    func test_process_retriesUntilSuccessWithinMaxRetries() async {
        let mockLogService = LogDBService(db: DummyLogDB())
        let mockLLM = MockLLMRunner()
        
        // First two attempts fail via empty tokens & shouldThrow, third succeeds
        var attempt = 0
        mockLLM.tokensToEmit = ["success"]
        
        class FlakyLLMRunner: MockLLMRunner {
            var attempt = 0
            
            override func generate(with prompt: String, maxTokens: Int32) -> AsyncThrowingStream<String, Error> {
                attempt += 1
                if attempt < 3 {
                    return AsyncThrowingStream { continuation in
                        continuation.finish(throwing: NSError(domain: "Flaky", code: attempt))
                    }
                } else {
                    return super.generate(with: prompt, maxTokens: maxTokens)
                }
            }
        }
        
        let flakyLLM = FlakyLLMRunner()
        flakyLLM.tokensToEmit = ["OK"]
        
        let viewModel = HomeViewModel(logService: mockLogService, llmRunner: flakyLLM)
        let log = LogEntry(value: 7, timestamp: Date())
        
        let output = await viewModel.process(log)
        
        XCTAssertEqual(output, "OK")
        XCTAssertEqual(flakyLLM.attempt, 3, "Expected two failures then one success")
    }
    
    func test_process_returnsFallbackMessageAfterMaxRetries() async {
        let mockLogService = LogDBService(db: DummyLogDB())
        let mockLLM = MockLLMRunner()
        mockLLM.shouldThrow = true
        
        let viewModel = HomeViewModel(logService: mockLogService, llmRunner: mockLLM)
        let log = LogEntry(value: 99, timestamp: Date())
        
        let output = await viewModel.process(log)
        
        XCTAssertEqual(output, "LLM generation Failed after retries...")
    }
    
    // MARK: - Tests for start service
    
    func test_startService_emitsRecentEvent() {
        let logService = LogDBService(db: DummyLogDB())
        let mockLLM = MockLLMRunner()
        let viewModel = HomeViewModel(logService: logService, llmRunner: mockLLM)
        
        let expectation = XCTestExpectation(description: "resentEvent is updated")
        
        let cancellable = viewModel.$resentEvent
            .compactMap { $0 }
            .sink { _ in
                expectation.fulfill()
            }
        
        viewModel.startService()
        
        wait(for: [expectation], timeout: 3.0)
        cancellable.cancel()
        
        XCTAssertNotNil(viewModel.resentEvent, "Expected resentEvent to receive at least one value")
    }
}
