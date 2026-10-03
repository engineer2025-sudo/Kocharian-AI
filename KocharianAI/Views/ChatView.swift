import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var models: ModelManager
    @StateObject private var model = ChatViewModel()
    @StateObject private var recorder = AudioRecorder()
    @State private var showSettings = false
    @State private var showModels = false

    private var conversation: Conversation? { store.selected }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = model.errorBanner { errorBanner(banner) }
            if let setup = setupHint { setupBanner(setup) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let conversation, !conversation.messages.isEmpty {
                            ForEach(conversation.messages) { message in
                                MessageRow(
                                    message: message,
                                    isLastAssistant: message.id == conversation.messages.last?.id
                                        && message.role == .assistant,
                                    onRegenerate: { model.regenerate(store: store, settings: settings) },
                                    onEdit: { text in
                                        model.edit(message.id, newText: text, store: store, settings: settings)
                                    },
                                    onDelete: {
                                        if let id = store.selectedID {
                                            store.removeMessage(message.id, in: id)
                                        }
                                    }
                                )
                                .id(message.id)
                            }
                            if let status = model.statusText {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(status).font(.caption).foregroundStyle(.secondary)
                                }
                                .id("status")
                            }
                            Color.clear.frame(height: 8).id("bottom")
                        } else {
                            EmptyChatView { suggestion in
                                model.draft = suggestion
                            }
                            .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: conversation?.messages.last?.content) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: conversation?.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            ComposerView(model: model,
                         recorder: recorder,
                         onSend: { model.send(store: store, settings: settings) },
                         onStop: { model.stop() })
        }
        .background(Theme.canvas)
        .navigationTitle(conversation?.title ?? "Kocharian AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { store.newConversation() } label: { Label("New chat", systemImage: "square.and.pencil") }
                    if let conversation {
                        ShareLink(item: conversation.markdown,
                                  preview: SharePreview(conversation.title)) {
                            Label("Export as Markdown", systemImage: "square.and.arrow.up")
                        }
                        Button { store.togglePin(conversation.id) } label: {
                            Label(conversation.pinned ? "Unpin" : "Pin",
                                  systemImage: conversation.pinned ? "pin.slash" : "pin")
                        }
                    }
                    Divider()
                    Button { showModels = true } label: { Label("Models", systemImage: "cpu") }
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { store.newConversation() } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(settings).environmentObject(models)
        }
        .sheet(isPresented: $showModels) {
            ModelsView().environmentObject(models).environmentObject(settings)
        }
        .onChange(of: recorder.errorMessage) { _, value in
            if let value { model.errorBanner = value }
        }
    }

    /// Nudges the user to finish setup (pick an engine that can actually answer).
    private var setupHint: String? {
        guard model.errorBanner == nil else { return nil }
        return EngineRouter.shared.unavailableReason(for: settings.snapshot)
    }

    private func setupBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "cpu")
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.footnote)
                HStack(spacing: 12) {
                    Button("Get a model") { showModels = true }
                        .font(.footnote.weight(.semibold))
                    Button("Settings") { showSettings = true }
                        .font(.footnote)
                }
            }
            Spacer()
        }
        .padding(10)
        .foregroundStyle(Theme.accent)
        .background(Theme.accent.opacity(0.10))
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.footnote)
            Spacer()
            Button { model.errorBanner = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
        .padding(10)
        .foregroundStyle(.orange)
        .background(Color.orange.opacity(0.12))
    }
}

struct EmptyChatView: View {
    var onPick: (String) -> Void

    private let suggestions = [
        "Explain the difference between async and await in Swift",
        "Summarise the text in a photo I’m about to attach",
        "Write a haiku about offline AI",
        "Give me three ideas for dinner with rice and eggs"
    ]

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Kocharian AI")
                .font(.largeTitle.bold())
            Text("Private chat, on-device. Attach a photo, a voice note or a document and ask about it.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { onPick(suggestion) } label: {
                        HStack {
                            Text(suggestion)
                                .font(.footnote)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}
