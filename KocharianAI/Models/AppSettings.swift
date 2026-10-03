import Foundation
import SwiftUI

/// Which brain answers the user. Both run on this device — there is no server
/// mode and no cloud call anywhere in the app.
enum EngineKind: String, CaseIterable, Identifiable, Codable {
    /// Apple's built-in foundation model (iOS 26+, Apple Intelligence devices).
    case appleIntelligence
    /// A GGUF model you downloaded inside the app, run with llama.cpp.
    case onboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .onboard: return "On-board model"
        }
    }

    var shortTitle: String {
        switch self {
        case .appleIntelligence: return "Apple"
        case .onboard: return "On-board"
        }
    }

    var footnote: String {
        switch self {
        case .appleIntelligence:
            return "Apple's own model, built into iOS. Nothing to download, but it needs iOS 26 or later on an Apple Intelligence capable device."
        case .onboard:
            return "Runs a model you download inside the app — Qwen 2.5 1.5B Instruct (Q4_K_M) or a smaller one. Works completely offline once downloaded."
        }
    }

    var symbol: String {
        switch self {
        case .appleIntelligence: return "apple.logo"
        case .onboard: return "cpu"
        }
    }
}

/// User preferences, persisted in `UserDefaults` and published to SwiftUI.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var engineRaw: String { didSet { defaults.set(engineRaw, forKey: Key.engine) } }
    @Published var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) } }
    @Published var temperature: Double { didSet { defaults.set(temperature, forKey: Key.temperature) } }
    @Published var topP: Double { didSet { defaults.set(topP, forKey: Key.topP) } }
    @Published var maxTokens: Int { didSet { defaults.set(maxTokens, forKey: Key.maxTokens) } }
    @Published var threadCount: Int { didSet { defaults.set(threadCount, forKey: Key.threads) } }
    @Published var preferOnDeviceSpeech: Bool { didSet { defaults.set(preferOnDeviceSpeech, forKey: Key.speech) } }

    private enum Key {
        static let engine = "engineKind"
        static let systemPrompt = "systemPrompt"
        static let temperature = "temperature"
        static let topP = "topP"
        static let maxTokens = "maxTokens"
        static let threads = "threadCount"
        static let speech = "preferOnDeviceSpeech"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engineRaw = defaults.string(forKey: Key.engine) ?? EngineKind.appleIntelligence.rawValue
        systemPrompt = defaults.string(forKey: Key.systemPrompt) ?? AppSettings.defaultSystemPrompt
        temperature = defaults.object(forKey: Key.temperature) as? Double ?? 0.7
        topP = defaults.object(forKey: Key.topP) as? Double ?? 0.95
        maxTokens = defaults.object(forKey: Key.maxTokens) as? Int ?? 768
        threadCount = defaults.object(forKey: Key.threads) as? Int ?? 0      // 0 = automatic
        preferOnDeviceSpeech = defaults.object(forKey: Key.speech) as? Bool ?? true
    }

    static let defaultSystemPrompt = """
    You are Kocharian AI, a helpful, knowledgeable and friendly assistant. \
    Answer clearly and concisely, use Markdown for structure, and show code in fenced code blocks. \
    When the user attaches an image, audio file or document, the extracted text is given to you — use it.
    """

    var engine: EngineKind {
        get { EngineKind(rawValue: engineRaw) ?? .appleIntelligence }
        set { engineRaw = newValue.rawValue }
    }

    /// Threads llama.cpp should use: the performance cores, never more.
    var resolvedThreadCount: Int {
        if threadCount > 0 { return threadCount }
        return max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
    }

    struct Snapshot {
        var engine: EngineKind
        var systemPrompt: String
        var temperature: Double
        var topP: Double
        var maxTokens: Int
        var threads: Int
    }

    var snapshot: Snapshot {
        Snapshot(engine: engine,
                 systemPrompt: systemPrompt,
                 temperature: temperature,
                 topP: topP,
                 maxTokens: maxTokens,
                 threads: resolvedThreadCount)
    }
}
