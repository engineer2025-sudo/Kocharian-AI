import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var probeState: ProbeState = .idle
    @State private var onDeviceStatus: String?

    private enum ProbeState: Equatable {
        case idle, testing, ok(String), failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
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

                    if settings.engine == .onDevice, let onDeviceStatus {
                        Label(onDeviceStatus, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if settings.engine == .onDevice {
                        Label("Apple Intelligence model ready", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("Model")
                }

                if settings.engine == .server {
                    Section {
                        TextField("http://192.168.1.42:3000", text: $settings.serverURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack {
                                Text("Test connection")
                                Spacer()
                                switch probeState {
                                case .idle: EmptyView()
                                case .testing: ProgressView().controlSize(.small)
                                case .ok(let model):
                                    Label(model, systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                case .failed(let message):
                                    Label(message, systemImage: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .lineLimit(2)
                                }
                            }
                        }
                    } header: {
                        Text("Server")
                    } footer: {
                        Text("Run `npm start` in the Kocharian-AI folder on your computer, then enter the LAN address it prints. Phone and computer must share a Wi-Fi network.")
                    }
                }

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
                    Stepper("Max new tokens: \(settings.maxTokens)",
                            value: $settings.maxTokens, in: 128...4096, step: 128)
                    Toggle("Prefer on-device speech recognition", isOn: $settings.preferOnDeviceSpeech)
                } header: {
                    Text("Generation")
                }

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

                Section {
                    LabeledContent("Version", value: "1.0")
                    Label("Chats, photos, voice notes and documents are processed on this device (or on your own computer). Nothing is sent to a third-party cloud.",
                          systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { refreshOnDeviceStatus() }
            .onChange(of: settings.engineRaw) { _ in refreshOnDeviceStatus() }
        }
    }

    private func refreshOnDeviceStatus() {
        onDeviceStatus = EngineRouter.shared
            .engine(for: .onDevice)
            .unavailableReason(for: settings.snapshot)
    }

    private func testConnection() async {
        probeState = .testing
        let engine = EngineRouter.shared.engine(for: .server) as? KocharianServerEngine
        let url = settings.normalizedServerURL
        guard let engine, !url.isEmpty else {
            probeState = .failed("Enter an address first")
            return
        }
        switch await engine.probe(url) {
        case .success(let model):
            probeState = .ok(model)
        case .failure(let error):
            probeState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
