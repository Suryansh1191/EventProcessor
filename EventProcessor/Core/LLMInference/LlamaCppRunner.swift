import Foundation
import llama

class LlamaCppRunner: LLMInferenceProtocol {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>!
    private var vocab: OpaquePointer?
    
    //indicator
    var isLoaded: Bool
    
    enum LlamaError: Error {
        case modelNotFound(String)
        case contextCreationFailed
        case tokenizationFailed
        case decodingFailed
    }

    init() {
        llama_backend_init()
        isLoaded = false
    }

    deinit {
        offloadModel()
        llama_backend_free()
    }

    // Lifecycle Management
    func loadModel(path: String) throws {
        try loadModel(path: path, contextSize: LLMConstants.defaultContextSize)
    }

    func loadModel(path: String, contextSize: UInt32) throws {

        // Loading Model with load params
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99
        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.modelNotFound(path)
        }
        self.model = model

        // context params
        let threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = contextSize
        ctxParams.n_threads = Int32(threads)
        ctxParams.n_threads_batch = Int32(threads)
        
        guard let context = llama_init_from_model(model, ctxParams) else {
            throw LlamaError.contextCreationFailed
        }
        
        self.vocab = llama_model_get_vocab(model)
        self.context = context
        self.isLoaded = true
    }

    /// Offloads the model and context from memory
    func offloadModel() {
        if let context {
            llama_free(context)
            self.context = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
        isLoaded = false
    }

    // Inference / Generation
    func generate(with prompt: String) -> AsyncThrowingStream<String, any Error> {
        return generate(with: prompt, maxTokens: LLMConstants.maxTokens)
    }
    
    func generate(with prompt: String, maxTokens: Int32) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var nLen: Int32 = LLMConstants.defaultNlength
                    var nCur: Int32 = 0
                    var nDecode: Int32 = 0
                    var batch = llama_batch_init(512, 0, 1)
                    var temporaryCChars: [CChar] = []
                    
                    let sparams = llama_sampler_chain_default_params()
                    self.sampler = llama_sampler_chain_init(sparams)
                    llama_sampler_chain_add(
                        self.sampler,
                        llama_sampler_init_temp(LLMConstants.defaultTemperature)
                    )
                    llama_sampler_chain_add(
                        self.sampler,
                        llama_sampler_init_greedy()
                    )
                    llama_sampler_chain_add(
                        self.sampler,
                        llama_sampler_init_dist(LLMConstants.samplerDist)
                    )
                    
                    defer {
                        llama_batch_free(batch)
                        let mem = llama_get_memory(context)
                        llama_memory_clear(mem, true)
                    }
                    
                    try tokenizeAndPrefill(
                        prompt: prompt,
                        batch: &batch,
                        nCur: &nCur,
                        nLen: &nLen
                    )
                    
                    try generationLoop(
                        batch: &batch,
                        nCur: &nCur,
                        nLen: &nLen,
                        temporaryCChars: &temporaryCChars,
                        nDecode: &nDecode,
                        maxTokens: maxTokens,
                        continuation: continuation
                    )
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func tokenizeAndPrefill(
        prompt: String,
        batch: inout llama_batch,
        nCur: inout Int32,
        nLen: inout Int32
    ) throws {
        
        // Tokenisation
        let tokensList = tokenize(text: prompt, addBos: true)
        let contextLimit = llama_n_ctx(context)
        let nKvReq = tokensList.count + Int(nLen - Int32(tokensList.count))
        if nKvReq > contextLimit {
            //TODO: Throw error
        }
        
        // pre-fill
        batch.n_tokens = 0
        for (i, token) in tokensList.enumerated() {
            llama_batch_add(
                batch: &batch,
                token: token,
                pos: Int32(i),
                seq_ids: [0],
                logits: (i == (tokensList.count - 1))
            )
        }

        if llama_decode(context, batch) != 0 {
            //TODO: Throw error
        }

        nCur = batch.n_tokens
    }
    
    private func generationLoop(
        batch: inout llama_batch,
        nCur: inout Int32,
        nLen: inout Int32,
        temporaryCChars: inout [CChar],
        nDecode: inout Int32,
        maxTokens: Int32,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws {
        
        while nCur < nLen && nCur - batch.n_tokens < maxTokens {
            
            var newTokenID: llama_token = 0
            newTokenID = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
            
            if llama_vocab_is_eog(vocab, newTokenID) || nCur == nLen {
                let newTokenStr = String(
                  decoding: Data(temporaryCChars.map { UInt8(bitPattern: $0) }),
                  as: UTF8.self
                )
                continuation.yield(newTokenStr)
                temporaryCChars.removeAll()
                break
            }
            
            let newTokenCChars = tokenToPiece(token: newTokenID)
            temporaryCChars.append(contentsOf: newTokenCChars)
            
            var utf8Buffer: [UInt8] = []
            for c in temporaryCChars where c != 0 {
                utf8Buffer.append(UInt8(bitPattern: c))
            }
            let newTokenStr: String

            if let string = String(bytes: utf8Buffer, encoding: .utf8)  {
                temporaryCChars.removeAll()
              newTokenStr = string
            } else {
              newTokenStr = ""
            }
            
            continuation.yield(newTokenStr)

            batch.n_tokens = 0
            llama_batch_add(
                batch: &batch,
                token: newTokenID,
                pos: nCur,
                seq_ids: [0],
                logits: true
            )

            nDecode += 1
            nCur += 1

            if llama_decode(context, batch) != 0 {
                //TODO: Throw error
            }
            
        }
        
        continuation.finish()
        
    }

    // MARK: - Helpers
    private func tokenize(text: String, addBos: Bool) -> [llama_token] {

        // Create a stable, null-terminated UTF-8 buffer
        var utf8 = Array(text.utf8)
        utf8.append(0)

        let maxTokens = utf8.count + (addBos ? 1 : 0) + 16
        var tokens = [llama_token](repeating: 0, count: maxTokens)

        let count = llama_tokenize(
            vocab,
            utf8,
            Int32(utf8.count - 1),
            &tokens,
            Int32(maxTokens),
            addBos,
            false
        )

        guard count >= 0 else { return [] }
        return Array(tokens.prefix(Int(count)))
    }


    private func tokenToPiece(token: llama_token) -> [CChar] {
      var buffer = [CChar](repeating: 0, count: 8)
      var nTokens = llama_token_to_piece(vocab, token, &buffer, 8, 0, false)

      if nTokens < 0 {
        let requiredSize = -nTokens
        buffer = [CChar](repeating: 0, count: Int(requiredSize))
        nTokens = llama_token_to_piece(vocab, token, &buffer, requiredSize, 0, false)
      }

      return Array(buffer.prefix(Int(nTokens)))
    }
    

    private func llama_batch_add(batch: inout llama_batch, token: llama_token, pos: Int32, seq_ids: [Int32], logits: Bool) {
        batch.token[Int(batch.n_tokens)] = token
        batch.pos[Int(batch.n_tokens)] = pos
        batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
        
        for (i, seq_id) in seq_ids.enumerated() {
            batch.seq_id[Int(batch.n_tokens)]![i] = seq_id
        }
        
        batch.logits[Int(batch.n_tokens)] = logits ? 1 : 0
        batch.n_tokens += 1
    }
}
