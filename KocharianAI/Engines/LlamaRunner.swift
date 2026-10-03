import Foundation
#if canImport(llama)
import llama
#endif

enum LlamaError: LocalizedError {
    case notLinked
    case loadFailed(String)
    case contextFailed
    case promptTooLong

    var errorDescription: String? {
        switch self {
        case .notLinked:
            return "The llama.cpp framework isn’t linked yet. See docs/XCODE.md ▸ “Add the llama.cpp engine”."
        case .loadFailed(let name):
            return "Couldn’t load \(name). The file may be incomplete — delete it in Models and download it again."
        case .contextFailed:
            return "Not enough memory to start this model. Try a smaller one, or lower the context size in Settings."
        case .promptTooLong:
            return "This conversation is longer than the model’s context window."
        }
    }
}

#if canImport(llama)

/// Thin Swift actor around the llama.cpp C API: loads a GGUF file and streams
/// tokens. One instance keeps the weights in memory between messages.
actor LlamaRunner {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var batch: llama_batch?

    private var loadedPath: String?
    private var contextSize: Int32 = 4096
    private var threadCount: Int32 = 4

    private var cursor: Int32 = 0
    private var produced = 0
    private var limit = 512
    private var pendingBytes: [CChar] = []

    private static var backendStarted = false

    var isLoaded: Bool { model != nil }
    var currentPath: String? { loadedPath }

    // MARK: - Lifecycle

    func load(path: String, contextSize: Int, threads: Int) throws {
        if loadedPath == path, model != nil { return }
        unload()

        if !Self.backendStarted {
            llama_backend_init()
            Self.backendStarted = true
        }

        self.contextSize = Int32(max(512, contextSize))
        self.threadCount = Int32(max(1, min(threads, ProcessInfo.processInfo.processorCount)))

        var modelParams = llama_model_default_params()
        modelParams.use_mmap = true          // page the weights in, keeps RSS low
        modelParams.use_mlock = false
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0         // no Metal in the simulator
        #else
        modelParams.n_gpu_layers = 999       // offload everything to the Apple GPU
        #endif

        guard let loaded = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.loadFailed((path as NSString).lastPathComponent)
        }
        model = loaded
        vocab = llama_model_get_vocab(loaded)
        loadedPath = path

        try makeContext()
        batch = llama_batch_init(512, 0, 1)
    }

    func unload() {
        if let batch { llama_batch_free(batch) }
        batch = nil
        if let sampler { llama_sampler_free(sampler) }
        sampler = nil
        if let context { llama_free(context) }
        context = nil
        if let model { llama_model_free(model) }
        model = nil
        vocab = nil
        loadedPath = nil
    }

    private func makeContext() throws {
        guard let model else { throw LlamaError.contextFailed }
        if let context { llama_free(context) }

        var params = llama_context_default_params()
        params.n_ctx = UInt32(contextSize)
        params.n_batch = 512
        params.n_threads = threadCount
        params.n_threads_batch = threadCount

        guard let ctx = llama_init_from_model(model, params) else {
            context = nil
            throw LlamaError.contextFailed
        }
        context = ctx
    }

    private func makeSampler(temperature: Double, topP: Double) {
        if let sampler { llama_sampler_free(sampler) }
        let chainParams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(chainParams) else { return }
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(Float(max(0.05, topP)), 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(max(0.01, temperature))))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))
        sampler = chain
    }

    // MARK: - Generation

    /// Evaluates the prompt and prepares the token loop.
    func begin(prompt: String, maxTokens: Int, temperature: Double, topP: Double) throws {
        guard model != nil, let vocab else { throw LlamaError.contextFailed }

        // A fresh context per answer keeps memory predictable and avoids
        // depending on KV-cache helpers that move between llama.cpp releases.
        try makeContext()
        makeSampler(temperature: temperature, topP: topP)

        guard let context, var workBatch = batch else { throw LlamaError.contextFailed }

        var tokens = tokenize(prompt, vocab: vocab, addSpecial: true)
        let room = Int(contextSize) - max(32, maxTokens)
        guard room > 16 else { throw LlamaError.promptTooLong }
        if tokens.count > room {
            tokens = Array(tokens.suffix(room))        // keep the most recent turns
        }

        produced = 0
        limit = max(16, maxTokens)
        cursor = 0
        pendingBytes = []

        var index = 0
        while index < tokens.count {
            let end = min(index + 512, tokens.count)
            clear(&workBatch)
            for position in index..<end {
                let isLast = position == tokens.count - 1
                add(&workBatch, token: tokens[position], position: Int32(position), logits: isLast)
            }
            guard llama_decode(context, workBatch) == 0 else {
                batch = workBatch
                throw LlamaError.contextFailed
            }
            index = end
        }
        cursor = Int32(tokens.count)
        batch = workBatch
    }

    /// Next piece of text, or `nil` when the model stopped.
    func next() -> String? {
        guard let context, let vocab, let sampler, var workBatch = batch else { return nil }
        guard produced < limit else { return nil }

        let token = llama_sampler_sample(sampler, context, -1)
        if llama_vocab_is_eog(vocab, token) { return nil }
        llama_sampler_accept(sampler, token)

        let piece = text(for: token, vocab: vocab)

        clear(&workBatch)
        add(&workBatch, token: token, position: cursor, logits: true)
        cursor += 1
        produced += 1
        let status = llama_decode(context, workBatch)
        batch = workBatch
        guard status == 0 else { return nil }

        return piece
    }

    /// Frees the KV cache after an answer without unloading the weights.
    func finish() {
        if let sampler { llama_sampler_free(sampler) }
        sampler = nil
    }

    // MARK: - Tokens ⇄ text

    private func tokenize(_ text: String, vocab: OpaquePointer, addSpecial: Bool) -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        let capacity = Int(utf8Count) + (addSpecial ? 1 : 0) + 1
        var result = [llama_token](repeating: 0, count: capacity)
        let count = llama_tokenize(vocab, text, utf8Count, &result, Int32(capacity), addSpecial, true)
        if count < 0 { return [] }
        return Array(result.prefix(Int(count)))
    }

    /// Converts one token to text, buffering incomplete UTF-8 sequences
    /// (emoji and CJK arrive in several tokens).
    private func text(for token: llama_token, vocab: OpaquePointer) -> String? {
        var buffer = [CChar](repeating: 0, count: 16)
        var written = llama_token_to_piece(vocab, token, &buffer, 16, 0, false)
        if written < 0 {
            let needed = Int(-written)
            buffer = [CChar](repeating: 0, count: needed)
            written = llama_token_to_piece(vocab, token, &buffer, Int32(needed), 0, false)
            guard written >= 0 else { return nil }
        }
        pendingBytes.append(contentsOf: buffer.prefix(Int(written)))

        let bytes = pendingBytes.map { UInt8(bitPattern: $0) }
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            return nil                    // wait for the rest of the character
        }
        pendingBytes = []
        return string
    }

    // MARK: - Batch helpers

    private func clear(_ batch: inout llama_batch) {
        batch.n_tokens = 0
    }

    private func add(_ batch: inout llama_batch, token: llama_token, position: Int32, logits: Bool) {
        let index = Int(batch.n_tokens)
        batch.token[index] = token
        batch.pos[index] = position
        batch.n_seq_id[index] = 1
        batch.seq_id[index]?[0] = 0
        batch.logits[index] = logits ? 1 : 0
        batch.n_tokens += 1
    }

    deinit {
        if let batch { llama_batch_free(batch) }
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }
}

#endif
