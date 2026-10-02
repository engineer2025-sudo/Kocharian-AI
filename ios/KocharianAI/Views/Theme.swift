import SwiftUI

enum Theme {
    static let accent = Color(red: 0.063, green: 0.639, blue: 0.498)      // #10a37f
    static let accentDeep = Color(red: 0.024, green: 0.235, blue: 0.212)
    static let userBubble = Color(red: 0.063, green: 0.639, blue: 0.498)
    static let assistantBubble = Color(.secondarySystemBackground)
    static let canvas = Color(.systemBackground)

    static let bubbleRadius: CGFloat = 18
}

/// Small rounded label used for attachment chips and badges.
struct Chip: View {
    let systemImage: String
    let title: String
    var tint: Color = Theme.accent
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(title)
                .font(.caption)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// Three dots that pulse while the model is thinking.
struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .opacity(opacity(for: index))
            }
        }
        .foregroundStyle(.secondary)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 3
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        let value = (phase + Double(index)).truncatingRemainder(dividingBy: 3)
        return 0.35 + 0.65 * (1 - value / 3)
    }
}
