import Foundation
import SwiftUI

/// Which brain answers the user.
enum EngineKind: String, CaseIterable, Identifiable, Codable {
    /// Apple's on-device foundation model (iOS 26+, Apple Intelligence devices).
    case onDevice
    /// Any OpenAI-compatible server you run yourself (llama.cpp, LM Studio,
    /// Ollama…) hosting a model such as Qwen 1.5B Instruct Q4_K_M.
    case localServer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: return "On-device (Apple Intelligence)"
        case .localServer: return "Local LLM server (Qwen GGUF)"
        }
    }

    var shortTitle: String {
        switch self {
        case .onDevice: return "On-device"
        case .localServer: return "Server"
        }
    }

    var footnote: String {
        switch self {
        case .onDevice:
            return "Runs entirely on this iPhone. Needs iOS 26 or later on an Apple Intelligence capable device. Nothing leaves the phone."
        case .localServer:
            return "Streams from a model you host yourself — llama.cpp, LM Studio or Ollama serving Qwen 1.5B — over your own Wi-Fi."
        }
    }
}

/// User preferences, persisted in `UserDefaults` and published to SwiftUI.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var engineRaw: String { didSet { defaults.set(engineRaw, forKey: Key.engine) } }
    @Published var serverURL: String { didSet { defaults.set(serverURL, forKey: Key.serverURL) } }
    @Published var modelName: String { didSet { defaults.set(modelName, forKey: Key.modelName) } }
    @Published var apiKey: String { didSet { defaults.set(apiKey, forKey: Key.apiKey) } }
    @Published var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) } }
    @Published var temperature: Double { didSet { defaults.set(temperature, forKey: Key.temperature) } }
    @Published var maxTokens: Int { didSet { defaults.set(maxTokens, forKey: Key.maxTokens) } }
    @Published var preferOnDeviceSpeech: Bool { didSet { defaults.set(preferOnDeviceSpeech, forKey: Key.onDeviceSpeech) } }

    private enum Key {
        static let engine = "engineKind"
        static let serverURL = "serverURL"
        static let modelName = "modelName"
        static let apiKey = "apiKey"
        static let systemPrompt = "systemPrompt"
        static let temperature = "temperature"
        static let maxTokens = "maxTokens"
        static let onDeviceSpeech = "preferOnDeviceSpeech"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engineRaw = defaults.string(forKey: Key.engine) ?? EngineKind.onDevice.rawValue
        serverURL = defaults.string(forKey: Key.serverURL) ?? ""
        modelName = defaults.string(forKey: Key.modelName) ?? "qwen2.5-1.5b-instruct"
        apiKey = defaults.string(forKey: Key.apiKey) ?? ""
        systemPrompt = defaults.string(forKey: Key.systemPrompt) ?? AppSettings.defaultSystemPrompt
        temperature = defaults.object(forKey: Key.temperature) as? Double ?? 0.7
        maxTokens = defaults.object(forKey: Key.maxTokens) as? Int ?? 768
        preferOnDeviceSpeech = defaults.object(forKey: Key.onDeviceSpeech) as? Bool ?? true
    }

    static let defaultSystemPrompt = """
    You are Kocharian AI, a helpful, knowledgeable and friendly assistant. \
    Answer clearly and concisely, use Markdown for structure, and show code in fenced code blocks. \
    When the user attaches an image, audio file or document, the extracted text is given to you — use it.
    """

    var engine: EngineKind {
        get { EngineKind(rawValue: engineRaw) ?? .onDevice }
        set { engineRaw = newValue.rawValue }
    }

    /// Normalised server address, e.g. `http://192.168.1.42:3000`.
    var normalizedServerURL: String {
        var value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let lower = value.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            value = "http://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        if let url = URL(string: value), url.port == nil, !value.lowercased().hasPrefix("https://") {
            value += ":8080"
        }
        return value
    }

    struct Snapshot {
        var engine: EngineKind
        var serverURL: String
        var modelName: String
        var apiKey: String
        var systemPrompt: String
        var temperature: Double
        var maxTokens: Int
    }

    var snapshot: Snapshot {
        Snapshot(engine: engine,
                 serverURL: normalizedServerURL,
                 modelName: modelName,
                 apiKey: apiKey,
                 systemPrompt: systemPrompt,
                 temperature: temperature,
                 maxTokens: maxTokens)
    }
}
