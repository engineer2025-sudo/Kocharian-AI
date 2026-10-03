import Foundation
import SwiftUI

/// Drives one chat: composing, streaming, stopping, regenerating.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var draft: String = ""
    @Published var pendingAttachments: [Attachment] = []
    @Published var isResponding = false
    @Published var statusText: String?
    @Published var isAnalyzing = false
    @Published var errorBanner: String?

    private var streamTask: Task<Void, Never>?
    private let router = EngineRouter.shared

    var canSend: Bool {
        !isResponding && !isAnalyzing &&
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
    }

    // MARK: - Attachments

    func add(_ attachment: Attachment) {
        pendingAttachments.append(attachment)
    }

    func removeAttachment(_ id: Attachment.ID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    // MARK: - Sending

    func send(store: ChatStore, settings: AppSettings) {
        guard canSend, let conversationID = store.selectedID else { return }

        let message = ChatMessage(role: .user,
                                  content: draft.trimmingCharacters(in: .whitespacesAndNewlines),
                                  attachments: pendingAttachments)
        draft = ""
        pendingAttachments = []
        store.append(message, to: conversationID)
        respond(store: store, settings: settings, conversationID: conversationID)
    }

    /// Re-asks the model for the last answer.
    func regenerate(store: ChatStore, settings: AppSettings) {
        guard let conversationID = store.selectedID,
              let conversation = store.selected,
              let last = conversation.messages.last, last.role == .assistant else { return }
        store.truncate(from: last.id, in: conversationID, inclusive: true)
        resetContext(store: store, conversationID: conversationID)
        respond(store: store, settings: settings, conversationID: conversationID)
    }

    /// Replaces a user message and re-runs the conversation from there.
    func edit(_ messageID: ChatMessage.ID, newText: String, store: ChatStore, settings: AppSettings) {
        guard let conversationID = store.selectedID else { return }
        store.update(messageID: messageID, in: conversationID) { $0.content = newText }
        store.truncate(from: messageID, in: conversationID, inclusive: false)
        resetContext(store: store, conversationID: conversationID)
        respond(store: store, settings: settings, conversationID: conversationID)
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isResponding = false
        statusText = nil
    }

    func resetContext(store: ChatStore, conversationID: Conversation.ID) {
        router.forget(conversation: conversationID)
    }

    // MARK: - Core loop

    private func respond(store: ChatStore, settings: AppSettings, conversationID: Conversation.ID) {
        guard let conversation = store.conversations.first(where: { $0.id == conversationID }) else { return }

        let snapshot = settings.snapshot
        let engine = router.engine(for: snapshot.engine)

        if let reason = engine.unavailableReason(for: snapshot) {
            var failed = ChatMessage(role: .assistant, content: "")
            failed.errorText = reason
            failed.engine = engine.displayName
            store.append(failed, to: conversationID)
            errorBanner = reason
            return
        }

        var placeholder = ChatMessage(role: .assistant, content: "")
        placeholder.isStreaming = true
        placeholder.engine = engine.displayName
        store.append(placeholder, to: conversationID)
        let placeholderID = placeholder.id

        isResponding = true
        statusText = "Thinking…"

        let request = EngineRequest(conversationID: conversationID,
                                    history: conversation.messages.filter { $0.role != .system },
                                    settings: snapshot)

        streamTask = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            do {
                for try await event in engine.stream(request) {
                    try Task.checkCancellation()
                    switch event {
                    case .status(let text):
                        self.statusText = text
                    case .token(let delta):
                        buffer += delta
                        self.statusText = nil
                        store.update(messageID: placeholderID, in: conversationID) {
                            $0.content = buffer
                            $0.isStreaming = true
                        }
                    case .done(let text, let tps):
                        if !text.isEmpty { buffer = text }
                        store.update(messageID: placeholderID, in: conversationID) {
                            $0.content = buffer
                            $0.isStreaming = false
                            $0.tokensPerSecond = tps
                        }
                    }
                }
            } catch is CancellationError {
                // keep whatever was streamed so far
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.errorBanner = message
                store.update(messageID: placeholderID, in: conversationID) {
                    $0.errorText = message
                    $0.isStreaming = false
                }
            }

            store.update(messageID: placeholderID, in: conversationID) {
                $0.content = buffer
                $0.isStreaming = false
            }
            if buffer.isEmpty, store.selected?.messages.last?.errorText == nil {
                store.removeMessage(placeholderID, in: conversationID)
            }
            store.scheduleSave()
            self.isResponding = false
            self.statusText = nil
            self.streamTask = nil
        }
    }
}
