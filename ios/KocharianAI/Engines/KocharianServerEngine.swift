import Foundation

/// Streams from the Kocharian AI Node server (`npm start`) running the
/// on-board Qwen 1.5B Q4_K_M GGUF model, over Server-Sent Events.
final class KocharianServerEngine: ChatEngine {
    let displayName = "Kocharian server"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func unavailableReason(for settings: AppSettings.Snapshot) -> String? {
        settings.serverURL.isEmpty
            ? "Set the address of the computer running `npm start` in Settings ▸ Server."
            : nil
    }

    /// Quick reachability + model probe used by the Settings screen.
    func probe(_ urlString: String) async -> Result<String, Error> {
        guard let url = URL(string: urlString + "/api/health") else {
            return .failure(EngineError.notConfigured("That doesn’t look like a valid address."))
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure(EngineError.transport("The server answered with an unexpected status."))
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let model = (json?["model"] as? [String: Any])?["id"] as? String
            return .success(model ?? "connected")
        } catch {
            return .failure(EngineError.transport(error.localizedDescription))
        }
    }

    func stream(_ request: EngineRequest) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !request.settings.serverURL.isEmpty,
                          let url = URL(string: request.settings.serverURL + "/api/chat") else {
                        throw EngineError.notConfigured(
                            "Set the address of the computer running `npm start` in Settings ▸ Server.")
                    }
                    guard let last = request.history.last(where: { $0.role == .user }) else {
                        throw EngineError.transport("Nothing to send.")
                    }

                    var body: [String: Any] = [
                        "content": last.promptText,
                        "systemPrompt": request.settings.systemPrompt,
                        "options": [
                            "temperature": request.settings.temperature,
                            "maxTokens": request.settings.maxTokens
                        ]
                    ]
                    if let remoteID = request.remoteID { body["conversationId"] = remoteID }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

                    continuation.yield(.status("Connecting to \(url.host ?? "server")…"))

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw EngineError.transport("No response from the server.")
                    }
                    guard http.statusCode == 200 else {
                        throw EngineError.transport("Server returned HTTP \(http.statusCode).")
                    }

                    var full = ""
                    var tokensPerSecond: Double?

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "meta":
                            if let id = event["conversationId"] as? String {
                                continuation.yield(.remoteID(id))
                            }
                        case "status":
                            if let message = event["message"] as? String {
                                continuation.yield(.status(message))
                            }
                        case "token":
                            if let text = event["text"] as? String, !text.isEmpty {
                                full += text
                                continuation.yield(.token(text))
                            }
                        case "done":
                            if let text = event["done"] as? String { full = text }
                            if let text = event["text"] as? String, !text.isEmpty { full = text }
                            if let stats = event["stats"] as? [String: Any] {
                                tokensPerSecond = stats["tokensPerSecond"] as? Double
                                    ?? stats["tps"] as? Double
                            }
                        case "error":
                            throw EngineError.transport(event["message"] as? String ?? "Server error.")
                        default:
                            break
                        }
                    }

                    continuation.yield(.done(text: full, tokensPerSecond: tokensPerSecond))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as EngineError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: EngineError.transport(friendly(error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func friendly(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return "Can’t reach the server. Check the address, and that your iPhone and computer are on the same Wi-Fi."
        case NSURLErrorTimedOut:
            return "The server took too long to answer."
        case NSURLErrorNotConnectedToInternet:
            return "This iPhone isn’t on a network."
        default:
            return nsError.localizedDescription
        }
    }
}
