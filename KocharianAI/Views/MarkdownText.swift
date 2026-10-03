import SwiftUI
import UIKit

/// Renders assistant output: Markdown for prose, a proper scrollable card with
/// a copy button for fenced code blocks.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownText.blocks(in: text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let value):
                    Text(MarkdownText.attributed(value))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language, let value):
                    CodeBlock(language: language, code: value)
                }
            }
        }
    }

    // MARK: - Parsing

    enum Block {
        case prose(String)
        case code(language: String?, code: String)
    }

    static func blocks(in text: String) -> [Block] {
        var result: [Block] = []
        var prose: [String] = []
        var code: [String] = []
        var language: String?
        var inCode = false

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    result.append(.code(language: language, code: code.joined(separator: "\n")))
                    code = []
                    language = nil
                    inCode = false
                } else {
                    if !prose.isEmpty {
                        result.append(.prose(prose.joined(separator: "\n")))
                        prose = []
                    }
                    let fence = line.trimmingCharacters(in: .whitespaces).dropFirst(3)
                        .trimmingCharacters(in: .whitespaces)
                    language = fence.isEmpty ? nil : String(fence)
                    inCode = true
                }
                continue
            }
            if inCode { code.append(line) } else { prose.append(line) }
        }

        if inCode, !code.isEmpty {
            result.append(.code(language: language, code: code.joined(separator: "\n")))
        } else if !prose.isEmpty {
            result.append(.prose(prose.joined(separator: "\n")))
        }
        return result.isEmpty ? [.prose(text)] : result
    }

    static func attributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let value = try? AttributedString(markdown: markdown, options: options) {
            return value
        }
        return AttributedString(markdown)
    }
}

struct CodeBlock: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
