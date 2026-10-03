import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var models: ModelManager
    @Environment(\.dismiss) private var dismiss

    @State private var appleStatus: String?
    @State private var showModels = false

    var body: some View {
        NavigationStack {
            Form {
                engineSection
                if settings.engine == .onboard { onboardSection }
                generationSection
                promptSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showModels) {
                ModelsView()
                    .environmentObject(models)
                    .environmentObject(settings)
            }
            .task { refreshAppleStatus() }
            .onChange(of: settings.engineRaw) { _, _ in refreshAppleStatus() }
        }
    }

    // MARK: - Sections

    private var engineSection: some View {
        Section {
            Picker("Engine", selection: Binding(get: { settings.engine },
                                                set: { settings.engine = $0 })) {
                ForEach(EngineKind.allCases) { kind in
                    Text(kind.shortTitle).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Text(settings.engine.footnote)
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.engine == .appleIntelligence {
                if let appleStatus {
                    Label(appleStatus, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Apple Intelligence is ready", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Text("Answers come from")
        }
    }

    private var onboardSection: some View {
        Section {
            Button {
                showModels = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Model")
                            .foregroundStyle(.primary)
                        Text(models.selectedModel?.displayName ?? "None downloaded yet")
                            .font(.caption)
                            .foregroundStyle(models.selectedModel == nil ? .orange : .secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if let model = models.selectedModel {
                LabeledContent("Size",
                               value: ByteCountFormatter.string(fromByteCount: model.byteSize,
                                                                countStyle: .file))
                LabeledContent("Context", value: "\(model.contextSize) tokens")
            }

            Picker("CPU threads", selection: $settings.threadCount) {
                Text("Automatic").tag(0)
                ForEach([2, 4, 6, 8], id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
        } header: {
            Text("On-board model")
        } footer: {
            Text("Qwen 2.5 1.5B Instruct (Q4_K_M) is the recommended download; 0.5B and SmolLM2 are lighter options for older devices. You can also import your own .gguf file.")
        }
    }

    private var generationSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.temperature, in: 0...1.5, step: 0.05)
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("Top-p")
                    Spacer()
                    Text(String(format: "%.2f", settings.topP))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.topP, in: 0.1...1.0, step: 0.05)
            }
            Stepper("Max new tokens: \(settings.maxTokens)",
                    value: $settings.maxTokens, in: 128...4096, step: 128)
            Toggle("Prefer on-device speech recognition", isOn: $settings.preferOnDeviceSpeech)
        } header: {
            Text("Generation")
        }
    }

    private var promptSection: some View {
        Section {
            TextEditor(text: $settings.systemPrompt)
                .frame(minHeight: 110)
                .font(.footnote)
            Button("Reset to default") {
                settings.systemPrompt = AppSettings.defaultSystemPrompt
            }
        } header: {
            Text("System prompt")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "1.0")
            Label("Chats, photos, voice notes and documents never leave this iPhone. Both engines run locally; the only network use is downloading a model you choose.",
                  systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("About")
        }
    }

    private func refreshAppleStatus() {
        appleStatus = EngineRouter.shared
            .engine(for: .appleIntelligence)
            .unavailableReason(for: settings.snapshot)
    }
}
