import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Talks to Apple's on-device foundation model (iOS 26+).
///
/// Nothing leaves the phone: no server, no API key, no network.
@MainActor
final class AppleIntelligenceEngine: ChatEngine {
    let displayName = "Apple Intelligence"

    /// One live session per conversation keeps multi-turn context for free.
    /// Typed as `Any` so the file still compiles against SDKs without FoundationModels.
    private var sessions: [UUID: Any] = [:]

    func forget(conversation id: UUID) {
        sessions[id] = nil
    }

    func unavailableReason(for settings: AppSettings.Snapshot) -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return Self.availabilityMessage()
        } else {
            return "On-device chat needs iOS 26 or later. Switch to the “On-board” engine in Settings and download a model."
        }
        #else
        return "This build was compiled without the FoundationModels SDK. Switch to the “On-board” engine in Settings and download a model."
        #endif
    }

    func stream(_ request: EngineRequest) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                if let reason = Self.availabilityMessage() {
                    continuation.finish(throwing: EngineError.unavailable(reason))
                    return
                }
                let task = self.startGeneration(request: request, continuation: continuation)
                continuation.onTermination = { _ in task.cancel() }
            } else {
                continuation.finish(throwing: EngineError.unavailable(
                    self.unavailableReason(for: request.settings) ?? "Unavailable"))
            }
            #else
            continuation.finish(throwing: EngineError.unavailable(
                self.unavailableReason(for: request.settings) ?? "Unavailable"))
            #endif
        }
    }

    // MARK: - FoundationModels specifics

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device doesn’t support Apple Intelligence. Switch to the “On-board” engine in Settings and download Qwen 2.5 1.5B Instruct."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off. Enable it in Settings ▸ Apple Intelligence & Siri, then come back."
            case .modelNotReady:
                return "The on-device model is still downloading. Try again in a few minutes."
            @unknown default:
                return "The on-device model isn’t available right now."
            }
        @unknown default:
            return "The on-device model isn’t available right now."
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func startGeneration(
        request: EngineRequest,
        continuation: AsyncThrowingStream<EngineEvent, Error>.Continuation
    ) -> Task<Void, Never> {
        Task { @MainActor in
            let started = Date()
            do {
                guard let prompt = request.history.last(where: { $0.role == .user })?.promptText,
                      !prompt.isEmpty else {
                    continuation.finish(throwing: EngineError.transport("Nothing to send."))
                    return
                }

                let session = self.session(for: request)
                let options = GenerationOptions(
                    temperature: request.settings.temperature,
                    maximumResponseTokens: max(64, request.settings.maxTokens)
                )
                let stream = session.streamResponse(to: prompt, options: options)

                var emitted = ""
                for try await partial in stream {
                    try Task.checkCancellation()
                    // Snapshots are cumulative — turn them into deltas.
                    let full = Self.text(from: partial)
                    if full.count >= emitted.count, full.hasPrefix(emitted) {
                        let delta = String(full.dropFirst(emitted.count))
                        if !delta.isEmpty { continuation.yield(.token(delta)) }
                    } else {
                        continuation.yield(.token(full))
                    }
                    emitted = full
                }

                let elapsed = Date().timeIntervalSince(started)
                let approxTokens = Double(emitted.count) / 4.0
                continuation.yield(.done(text: emitted,
                                         tokensPerSecond: elapsed > 0 ? approxTokens / elapsed : nil))
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: EngineError.transport(error.localizedDescription))
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func session(for request: EngineRequest) -> LanguageModelSession {
        if let cached = sessions[request.conversationID] as? LanguageModelSession {
            return cached
        }
        // Fresh session (first turn, or the app was relaunched): seed the
        // instructions with a compact recap so the model keeps the thread.
        var instructions = request.settings.systemPrompt
        let earlier = request.history.dropLast().suffix(8)
        if !earlier.isEmpty {
            let recap = earlier.map { message -> String in
                let who = message.role == .user ? "User" : "Assistant"
                return "\(who): \(message.promptText.prefix(500))"
            }.joined(separator: "\n")
            instructions += "\n\nEarlier in this conversation:\n\(recap)"
        }
        let session = LanguageModelSession(instructions: instructions)
        sessions[request.conversationID] = session
        return session
    }
    #endif

    /// Reads the text out of a streaming snapshot without depending on the
    /// exact shape of the element type (plain `String` on early SDKs, a
    /// snapshot struct with `.content` on newer ones).
    private static func text(from snapshot: Any) -> String {
        if let string = snapshot as? String { return string }
        let mirror = Mirror(reflecting: snapshot)
        if let content = mirror.children.first(where: { $0.label == "content" })?.value {
            if let string = content as? String { return string }
            return String(describing: content)
        }
        return String(describing: snapshot)
    }
}
