import Foundation
import SwiftUI

/// Owns every conversation and persists them as JSON inside the app container.
@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedID: Conversation.ID?
    @Published var searchText: String = ""

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(filename: String = "conversations.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent(filename)
        load()
        if conversations.isEmpty { newConversation() } else { selectedID = sorted.first?.id }
    }

    // MARK: - Derived

    var sorted: [Conversation] {
        conversations.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var filtered: [Conversation] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { conversation in
            conversation.title.lowercased().contains(needle)
                || conversation.messages.contains { $0.content.lowercased().contains(needle) }
        }
    }

    var selected: Conversation? {
        guard let selectedID else { return nil }
        return conversations.first { $0.id == selectedID }
    }

    func index(of id: Conversation.ID) -> Int? {
        conversations.firstIndex { $0.id == id }
    }

    // MARK: - Mutations

    @discardableResult
    func newConversation() -> Conversation {
        if let existing = conversations.first(where: { $0.messages.isEmpty }) {
            selectedID = existing.id
            return existing
        }
        let conversation = Conversation()
        conversations.append(conversation)
        selectedID = conversation.id
        scheduleSave()
        return conversation
    }

    func delete(_ id: Conversation.ID) {
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = sorted.first?.id }
        if conversations.isEmpty { newConversation() }
        scheduleSave()
    }

    func rename(_ id: Conversation.ID, to title: String) {
        guard let idx = index(of: id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[idx].title = trimmed.isEmpty ? "New chat" : trimmed
        scheduleSave()
    }

    func togglePin(_ id: Conversation.ID) {
        guard let idx = index(of: id) else { return }
        conversations[idx].pinned.toggle()
        scheduleSave()
    }

    func append(_ message: ChatMessage, to id: Conversation.ID) {
        guard let idx = index(of: id) else { return }
        conversations[idx].messages.append(message)
        conversations[idx].updatedAt = Date()
        if conversations[idx].title == "New chat", message.role == .user {
            let source = message.content.isEmpty
                ? (message.attachments.first?.name ?? "New chat")
                : message.content
            conversations[idx].title = Conversation.makeTitle(from: source)
        }
        scheduleSave()
    }

    func update(messageID: ChatMessage.ID, in id: Conversation.ID, _ body: (inout ChatMessage) -> Void) {
        guard let idx = index(of: id),
              let mIdx = conversations[idx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        body(&conversations[idx].messages[mIdx])
        conversations[idx].updatedAt = Date()
    }

    func removeMessage(_ messageID: ChatMessage.ID, in id: Conversation.ID) {
        guard let idx = index(of: id) else { return }
        conversations[idx].messages.removeAll { $0.id == messageID }
        scheduleSave()
    }

    /// Drops the message and everything after it (used by *edit* and *regenerate*).
    func truncate(from messageID: ChatMessage.ID, in id: Conversation.ID, inclusive: Bool) {
        guard let idx = index(of: id),
              let mIdx = conversations[idx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        let cut = inclusive ? mIdx : mIdx + 1
        conversations[idx].messages.removeSubrange(cut...)
        scheduleSave()
    }


    // MARK: - Persistence

    func scheduleSave() {
        saveTask?.cancel()
        let snapshot = conversations
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(conversations) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        conversations = (try? decoder.decode([Conversation].self, from: data)) ?? []
    }
}
