import Foundation

protocol LLMInferenceProtocol {
    var isLoaded: Bool { get }
    func loadModel(path: String, contextSize: UInt32) throws
    func loadModel(path: String) throws
    func offloadModel()
    func generate(with prompt: String, maxTokens: Int32) -> AsyncThrowingStream<String, Error>
    func generate(with prompt: String) -> AsyncThrowingStream<String, Error>
}
