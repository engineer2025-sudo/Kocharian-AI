import SwiftUI
import UniformTypeIdentifiers

/// Download, select, import and delete the on-board GGUF models.
struct ModelsView: View {
    @EnvironmentObject private var models: ModelManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var pendingDelete: InstalledModel?

    var body: some View {
        NavigationStack {
            List {
                if !models.installed.isEmpty { installedSection }
                availableSection
                storageSection
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showImporter = true } label: {
                        Label("Import .gguf", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    models.importModel(at: url)
                }
            }
            .alert("Delete model?", isPresented: Binding(get: { pendingDelete != nil },
                                                         set: { if !$0 { pendingDelete = nil } })) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    if let pendingDelete { models.delete(pendingDelete) }
                    pendingDelete = nil
                }
            } message: {
                Text("“\(pendingDelete?.displayName ?? "")” will be removed from this device. You can download it again later.")
            }
            .alert("Something went wrong",
                   isPresented: Binding(get: { models.lastError != nil },
                                        set: { if !$0 { models.lastError = nil } })) {
                Button("OK") { models.lastError = nil }
            } message: {
                Text(models.lastError ?? "")
            }
        }
    }

    // MARK: - Sections

    private var installedSection: some View {
        Section {
            ForEach(models.installed) { model in
                Button {
                    models.selectedModelID = model.id
                    settings.engine = .onboard
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: models.selectedModel?.id == model.id
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("\(ByteCountFormatter.string(fromByteCount: model.byteSize, countStyle: .file)) · \(model.contextSize) ctx\(model.imported ? " · imported" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { pendingDelete = model } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("On this device")
        } footer: {
            Text("The selected model answers when the engine is set to “On-board” in Settings.")
        }
    }

    private var availableSection: some View {
        Section {
            ForEach(ModelCatalog.all) { spec in
                ModelRow(spec: spec)
            }
        } header: {
            Text("Available to download")
        } footer: {
            Text("Models are downloaded straight from Hugging Face over Wi-Fi and stored on this device. Once a model is here, chatting needs no network at all.")
        }
    }

    private var storageSection: some View {
        Section {
            LabeledContent("Used by models",
                           value: ByteCountFormatter.string(fromByteCount: models.totalBytesOnDisk,
                                                            countStyle: .file))
            LabeledContent("Free space",
                           value: ByteCountFormatter.string(fromByteCount: ModelManager.freeDiskBytes,
                                                            countStyle: .file))
            LabeledContent("Device memory",
                           value: ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory),
                                                            countStyle: .memory))
        } header: {
            Text("Storage")
        } footer: {
            Text("A 1.5B Q4_K_M model needs roughly 2 GB of free memory while it answers. On a device with 4 GB of RAM or less, prefer the 0.5B or SmolLM2 models.")
        }
    }
}

/// One downloadable model with its progress / install state.
private struct ModelRow: View {
    let spec: ModelSpec
    @EnvironmentObject private var models: ModelManager

    private var state: DownloadState? { models.downloads[spec.id] }
    private var installed: Bool { models.isInstalled(spec) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(spec.name).font(.subheadline.weight(.medium))
                        if spec.id == ModelCatalog.defaultModelID {
                            Text("recommended")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Text(spec.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(spec.sizeText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                control
            }

            if let state, !installed {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: state.fraction)
                        .tint(Theme.accent)
                    HStack {
                        Text("\(ByteCountFormatter.string(fromByteCount: state.received, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: max(state.expected, spec.byteSize), countStyle: .file))")
                        Spacer()
                        Text(state.isPaused ? "Paused" : "\(Int(state.fraction * 100))%")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if let error = state.errorText {
                        Text(error).font(.caption2).foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var control: some View {
        if installed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
        } else if let state, !state.isPaused, state.errorText == nil {
            Button { models.pause(spec) } label: {
                Image(systemName: "pause.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        } else if state?.isPaused == true || state?.errorText != nil {
            HStack(spacing: 10) {
                Button { models.download(spec) } label: { Image(systemName: "play.circle") }
                    .buttonStyle(.plain)
                Button { models.cancel(spec) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
        } else {
            Button { models.download(spec) } label: {
                Text("Get").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)
        }
    }
}
