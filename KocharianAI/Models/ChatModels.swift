import Foundation

enum ChatRole: String, Codable, Hashable {
    case user
    case assistant
    case system
}

/// A file the user attached to a message. The heavy bytes stay on disk; the
/// text we extracted on-device (OCR / transcript) travels with the message.
struct Attachment: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case image, audio, document

        var symbol: String {
            switch self {
            case .image: return "photo"
            case .audio: return "waveform"
            case .document: return "doc.text"
            }
        }
    }

    var id: UUID = UUID()
    var name: String
    var kind: Kind
    /// OCR text, transcript or document text produced on-device.
    var extractedText: String = ""
    var byteCount: Int = 0
    var createdAt: Date = Date()
    /// File name inside the app's `Attachments` folder, when the original was kept.
    var fileName: String?

    var summaryLine: String {
        let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "no text found" }
        let oneLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        return String(oneLine.prefix(90)) + (oneLine.count > 90 ? "…" : "")
    }

    /// How the attachment is presented to the language model.
    var promptBlock: String {
        let label: String
        switch kind {
        case .image: label = "Text extracted from the image \"\(name)\""
        case .audio: label = "Transcript of the audio file \"\(name)\""
        case .document: label = "Contents of the document \"\(name)\""
        }
        let body = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "[\(label): no readable text found]" }
        return "[\(label)]\n\(body.prefix(6000))"
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var role: ChatRole
    var content: String
    var createdAt: Date = Date()
    var attachments: [Attachment] = []
    var engine: String?
    var tokensPerSecond: Double?
    var errorText: String?

    /// Not persisted — true while tokens are still arriving.
    var isStreaming: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, role, content, createdAt, attachments, engine, tokensPerSecond, errorText
    }

    /// User text plus the on-device analysis of every attachment.
    var promptText: String {
        var parts = attachments.map(\.promptBlock)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        return parts.joined(separator: "\n\n")
    }
}

struct Conversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = "New chat"
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var pinned: Bool = false

    var preview: String {
        messages.last(where: { $0.role != .system })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ") ?? "Empty conversation"
    }

    var markdown: String {
        var out = "# \(title)\n\n"
        let stamp = DateFormatter.localizedString(from: createdAt, dateStyle: .medium, timeStyle: .short)
        out += "_\(stamp) · Kocharian AI_\n\n"
        for message in messages where message.role != .system {
            out += message.role == .user ? "## You\n\n" : "## Kocharian AI\n\n"
            for attachment in message.attachments {
                out += "> 📎 \(attachment.name)\n\n"
            }
            out += message.content + "\n\n"
        }
        return out
    }

    static func makeTitle(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !cleaned.isEmpty else { return "New chat" }
        return String(cleaned.prefix(44))
    }
}
