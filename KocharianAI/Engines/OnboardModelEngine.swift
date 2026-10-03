import Foundation

/// Runs a GGUF model that lives on this device (downloaded in the Models
/// screen) with llama.cpp. No network, no server — airplane mode works.
@MainActor
final class OnboardModelEngine: ChatEngine {
    let displayName = "On-board model"

    #if canImport(llama)
    private let runner = LlamaRunner()
    #endif

    func unavailableReason(for settings: AppSettings.Snapshot) -> String? {
        #if canImport(llama)
        guard let model = ModelManager.shared.selectedModel else {
            return "No model on this device yet — open Models and download Qwen 2.5 1.5B Instruct (Q4_K_M), or a smaller one."
        }
        let path = ModelManager.shared.fileURL(for: model).path
        guard FileManager.default.fileExists(atPath: path) else {
            return "“\(model.displayName)” is missing from storage. Download it again in Models."
        }
        return nil
        #else
        return LlamaError.notLinked.errorDescription
        #endif
    }

    func stream(_ request: EngineRequest) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            #if canImport(llama)
            let task = Task { @MainActor in
                do {
                    guard let model = ModelManager.shared.selectedModel else {
                        throw EngineError.notConfigured(
                            "No model on this device yet — open Models and download one.")
                    }
                    let path = ModelManager.shared.fileURL(for: model).path
                    let settings = request.settings

                    if await runner.currentPath != path {
                        continuation.yield(.status("Loading \(model.displayName) into memory…"))
                    }
                    try await runner.load(path: path,
                                          contextSize: model.contextSize,
                                          threads: settings.threads)

                    let turns = request.history
                        .filter { $0.role != .system }
                        .map { (role: $0.role, text: $0.promptText) }
                    let prompt = model.template.render(system: settings.systemPrompt, messages: turns)

                    continuation.yield(.status("Thinking…"))
                    try await runner.begin(prompt: prompt,
                                           maxTokens: settings.maxTokens,
                                           temperature: settings.temperature,
                                           topP: settings.topP)

                    let started = Date()
                    var text = ""
                    var tokens = 0
                    let stops = model.template.stopStrings

                    while let piece = await runner.next() {
                        try Task.checkCancellation()
                        text += piece
                        tokens += 1
                        if Self.cut(&text, at: stops) { break }
                        continuation.yield(.token(piece))
                    }
                    await runner.finish()

                    let elapsed = Date().timeIntervalSince(started)
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.yield(.done(text: cleaned,
                                             tokensPerSecond: elapsed > 0 && tokens > 0
                                                ? Double(tokens) / elapsed : nil))
                    continuation.finish()
                } catch is CancellationError {
                    await runner.finish()
                    continuation.finish()
                } catch let error as LlamaError {
                    continuation.finish(throwing: EngineError.unavailable(
                        error.errorDescription ?? "The model failed to run."))
                } catch let error as EngineError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: EngineError.transport(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
            #else
            continuation.finish(throwing: EngineError.unavailable(
                LlamaError.notLinked.errorDescription ?? "llama.cpp is not linked."))
            #endif
        }
    }

    /// Trims the text at the first stop sequence. Returns `true` when one was hit.
    private static func cut(_ text: inout String, at stops: [String]) -> Bool {
        for stop in stops {
            if let range = text.range(of: stop) {
                text = String(text[text.startIndex..<range.lowerBound])
                return true
            }
        }
        return false
    }

    /// Frees the weights (called when the user deletes or swaps models).
    func unloadModel() {
        #if canImport(llama)
        Task { await runner.unload() }
        #endif
    }
}
