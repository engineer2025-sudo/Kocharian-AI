import Foundation

/// Everything an engine can report while answering.
enum EngineEvent {
    case status(String)
    /// Incremental text (delta, not cumulative).
    case token(String)
    case done(text: String, tokensPerSecond: Double?)
}

enum EngineError: LocalizedError {
    case notConfigured(String)
    case unavailable(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message), .unavailable(let message), .transport(let message):
            return message
        }
    }
}

struct EngineRequest {
    var conversationID: UUID
    /// Full history, oldest first, already including the new user turn.
    var history: [ChatMessage]
    var settings: AppSettings.Snapshot
}

protocol ChatEngine: AnyObject {
    var displayName: String { get }
    /// Human readable reason the engine cannot be used right now, or `nil`.
    func unavailableReason(for settings: AppSettings.Snapshot) -> String?
    func stream(_ request: EngineRequest) -> AsyncThrowingStream<EngineEvent, Error>
    func forget(conversation id: UUID)
}

extension ChatEngine {
    func forget(conversation id: UUID) {}
}

/// Picks the engine the user selected in Settings.
@MainActor
final class EngineRouter {
    static let shared = EngineRouter()

    private let onDevice = AppleIntelligenceEngine()
    private let localServer = LocalLLMEngine()

    func engine(for kind: EngineKind) -> ChatEngine {
        switch kind {
        case .onDevice: return onDevice
        case .localServer: return localServer
        }
    }

    func forget(conversation id: UUID) {
        onDevice.forget(conversation: id)
        localServer.forget(conversation: id)
    }

    /// `nil` when the selected engine is ready to answer.
    func unavailableReason(for settings: AppSettings.Snapshot) -> String? {
        engine(for: settings.engine).unavailableReason(for: settings)
    }
}
