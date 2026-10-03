import Foundation

/// Streams from any OpenAI-compatible server you run yourself — llama.cpp's
/// `llama-server`, LM Studio, Ollama (`/v1`), vLLM … — so the phone can use a
/// bigger model such as Qwen 1.5B Instruct Q4_K_M over your own Wi-Fi.
///
/// Nothing is sent to a third-party cloud: the address is whatever you type in
/// Settings, usually a machine on your LAN.
final class LocalLLMEngine: ChatEngine {
    let displayName = "Local LLM server"

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func unavailableReason(for settings: AppSettings.Snapshot) -> String? {
        settings.serverURL.isEmpty
            ? "Add the address of your local model server in Settings ▸ Server (for example http://192.168.1.42:8080)."
            : nil
    }

    // MARK: - Reachability

    /// Returns the first model id the server advertises.
    func probe(_ base: String) async -> Result<String, Error> {
        guard let url = URL(string: base + "/v1/models") else {
            return .failure(EngineError.notConfigured("That doesn’t look like a valid address."))
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failure(EngineError.transport("The server answered with an unexpected status."))
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let models = json?["data"] as? [[String: Any]]
            let name = models?.compactMap { $0["id"] as? String }.first
            return .success(name ?? "connected")
        } catch {
            return .failure(EngineError.transport(Self.friendly(error)))
        }
    }

    // MARK: - Streaming

    func stream(_ request: EngineRequest) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !request.settings.serverURL.isEmpty,
                          let url = URL(string: request.settings.serverURL + "/v1/chat/completions") else {
                        throw EngineError.notConfigured(
                            "Add the address of your local model server in Settings ▸ Server.")
                    }

                    var messages: [[String: String]] = [
                        ["role": "system", "content": request.settings.systemPrompt]
                    ]
                    for message in request.history.suffix(24) where message.role != .system {
                        messages.append([
                            "role": message.role == .user ? "user" : "assistant",
                            "content": message.promptText
                        ])
                    }

                    var body: [String: Any] = [
                        "messages": messages,
                        "stream": true,
                        "temperature": request.settings.temperature,
                        "max_tokens": request.settings.maxTokens
                    ]
                    if !request.settings.modelName.isEmpty {
                        body["model"] = request.settings.modelName
                    }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if !request.settings.apiKey.isEmpty {
                        urlRequest.setValue("Bearer \(request.settings.apiKey)",
                                            forHTTPHeaderField: "Authorization")
                    }
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

                    continuation.yield(.status("Contacting \(url.host ?? "server")…"))

                    let (bytes, response) = try await urlSession.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw EngineError.transport("No response from the server.")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw EngineError.transport("Server returned HTTP \(http.statusCode).")
                    }

                    let started = Date()
                    var full = ""
                    var chunks = 0

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if let error = json["error"] as? [String: Any] {
                            throw EngineError.transport(error["message"] as? String ?? "Server error.")
                        }
                        guard let choice = (json["choices"] as? [[String: Any]])?.first else { continue }
                        let delta = (choice["delta"] as? [String: Any])?["content"] as? String
                            ?? (choice["text"] as? String)
                        if let delta, !delta.isEmpty {
                            full += delta
                            chunks += 1
                            continuation.yield(.token(delta))
                        }
                    }

                    let elapsed = Date().timeIntervalSince(started)
                    continuation.yield(.done(text: full,
                                             tokensPerSecond: elapsed > 0 && chunks > 0
                                                ? Double(chunks) / elapsed : nil))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as EngineError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: EngineError.transport(Self.friendly(error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func friendly(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return "Can’t reach the server. Check the address, and that this iPhone and the computer are on the same Wi-Fi."
        case NSURLErrorTimedOut:
            return "The server took too long to answer."
        case NSURLErrorNotConnectedToInternet:
            return "This iPhone isn’t on a network."
        default:
            return nsError.localizedDescription
        }
    }
}
