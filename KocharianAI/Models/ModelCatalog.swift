import Foundation

/// A GGUF model the app can download and run on the device.
struct ModelSpec: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var detail: String
    /// Approximate download size in bytes (used for progress + warnings).
    var byteSize: Int64
    /// Direct download URL of the `.gguf` file.
    var urlString: String
    /// RAM the model needs once loaded, roughly `byteSize` + KV cache.
    var requiredMemoryMB: Int
    /// Prompt format used by the model.
    var template: PromptTemplate
    var recommendedContext: Int

    var url: URL? { URL(string: urlString) }
    var fileName: String { (url?.lastPathComponent).flatMap { $0.isEmpty ? nil : $0 } ?? "\(id).gguf" }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

/// How a conversation is turned into a single prompt string.
enum PromptTemplate: String, Codable, Hashable {
    case chatML      // Qwen, SmolLM2, many others
    case llama3
    case gemma
    case plain

    func render(system: String, messages: [(role: ChatRole, text: String)]) -> String {
        switch self {
        case .chatML:
            var out = system.isEmpty ? "" : "<|im_start|>system\n\(system)<|im_end|>\n"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                out += "<|im_start|>\(role)\n\(message.text)<|im_end|>\n"
            }
            out += "<|im_start|>assistant\n"
            return out

        case .llama3:
            var out = "<|begin_of_text|>"
            if !system.isEmpty {
                out += "<|start_header_id|>system<|end_header_id|>\n\n\(system)<|eot_id|>"
            }
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                out += "<|start_header_id|>\(role)<|end_header_id|>\n\n\(message.text)<|eot_id|>"
            }
            out += "<|start_header_id|>assistant<|end_header_id|>\n\n"
            return out

        case .gemma:
            var out = ""
            var first = true
            for message in messages {
                let role = message.role == .user ? "user" : "model"
                var text = message.text
                if first, message.role == .user, !system.isEmpty {
                    text = system + "\n\n" + text
                    first = false
                }
                out += "<start_of_turn>\(role)\n\(text)<end_of_turn>\n"
            }
            out += "<start_of_turn>model\n"
            return out

        case .plain:
            var out = system.isEmpty ? "" : system + "\n\n"
            for message in messages {
                out += (message.role == .user ? "User: " : "Assistant: ") + message.text + "\n"
            }
            out += "Assistant:"
            return out
        }
    }

    /// Extra stop strings on top of the model's own end-of-generation token.
    var stopStrings: [String] {
        switch self {
        case .chatML: return ["<|im_end|>", "<|im_start|>"]
        case .llama3: return ["<|eot_id|>", "<|start_header_id|>"]
        case .gemma: return ["<end_of_turn>"]
        case .plain: return ["\nUser:"]
        }
    }
}

enum ModelCatalog {
    /// The model the user asked for, first in the list.
    static let defaultModelID = "qwen2.5-1.5b-instruct-q4_k_m"

    static let all: [ModelSpec] = [
        ModelSpec(
            id: "qwen2.5-1.5b-instruct-q4_k_m",
            name: "Qwen 2.5 1.5B Instruct",
            detail: "Q4_K_M · best quality that still fits comfortably on a modern iPhone",
            byteSize: 1_117_320_768,
            urlString: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true",
            requiredMemoryMB: 2200,
            template: .chatML,
            recommendedContext: 4096
        ),
        ModelSpec(
            id: "qwen2.5-coder-1.5b-instruct-q4_k_m",
            name: "Qwen 2.5 Coder 1.5B",
            detail: "Q4_K_M · tuned for code and technical answers",
            byteSize: 1_117_320_768,
            urlString: "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf?download=true",
            requiredMemoryMB: 2200,
            template: .chatML,
            recommendedContext: 4096
        ),
        ModelSpec(
            id: "qwen2.5-0.5b-instruct-q4_k_m",
            name: "Qwen 2.5 0.5B Instruct",
            detail: "Q4_K_M · small and quick, good on older devices",
            byteSize: 398_458_880,
            urlString: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true",
            requiredMemoryMB: 900,
            template: .chatML,
            recommendedContext: 4096
        ),
        ModelSpec(
            id: "smollm2-360m-instruct-q8_0",
            name: "SmolLM2 360M Instruct",
            detail: "Q8_0 · tiny, very fast, basic answers",
            byteSize: 386_404_992,
            urlString: "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf?download=true",
            requiredMemoryMB: 700,
            template: .chatML,
            recommendedContext: 2048
        ),
        ModelSpec(
            id: "smollm2-135m-instruct-q8_0",
            name: "SmolLM2 135M Instruct",
            detail: "Q8_0 · smallest option, works on any device",
            byteSize: 145_000_000,
            urlString: "https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct-GGUF/resolve/main/smollm2-135m-instruct-q8_0.gguf?download=true",
            requiredMemoryMB: 400,
            template: .chatML,
            recommendedContext: 2048
        )
    ]

    static func spec(id: String) -> ModelSpec? {
        all.first { $0.id == id }
    }
}
