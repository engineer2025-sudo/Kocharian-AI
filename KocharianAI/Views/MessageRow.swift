import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    var isLastAssistant: Bool = false
    var onRegenerate: () -> Void = {}
    var onEdit: (String) -> Void = { _ in }
    var onDelete: () -> Void = {}

    @State private var showEditor = false
    @State private var editText = ""
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 40) }
            if message.role == .assistant { avatar }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if !message.attachments.isEmpty { attachmentStrip }

                if message.role == .user {
                    Text(message.content)
                        .textSelection(.enabled)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.userBubble,
                                    in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if let errorText = message.errorText {
                            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        if !message.content.isEmpty {
                            MarkdownText(text: message.content)
                        } else if message.isStreaming {
                            TypingIndicator()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.assistantBubble,
                                in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                }

                footer
            }

            if message.role == .assistant { Spacer(minLength: 40) }
            if message.role == .user { avatar }
        }
        .contextMenu {
            Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
            if message.role == .user {
                Button {
                    editText = message.content
                    showEditor = true
                } label: { Label("Edit & resend", systemImage: "pencil") }
            } else {
                Button(action: onRegenerate) { Label("Regenerate", systemImage: "arrow.clockwise") }
            }
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
        .alert("Edit message", isPresented: $showEditor) {
            TextField("Message", text: $editText)
            Button("Cancel", role: .cancel) {}
            Button("Resend") { onEdit(editText) }
        }
    }

    private var avatar: some View {
        Group {
            if message.role == .user {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill), in: Circle())
            } else {
                Image(systemName: "sparkle")
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.accent, in: Circle())
            }
        }
        .font(.footnote)
    }

    private var attachmentStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.attachments) { attachment in
                VStack(alignment: .leading, spacing: 4) {
                    Chip(systemImage: attachment.kind.symbol, title: attachment.name)
                    Text(attachment.summaryLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            if message.role == .assistant, !message.isStreaming, !message.content.isEmpty {
                Button { copy() } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                if isLastAssistant {
                    Button(action: onRegenerate) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                }
                if let tps = message.tokensPerSecond, tps > 0 {
                    Text(String(format: "%.1f tok/s", tps))
                }
                if let engine = message.engine {
                    Text(engine)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .labelStyle(.titleAndIcon)
    }

    private func copy() {
        UIPasteboard.general.string = message.content
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { copied = false }
        }
    }
}
