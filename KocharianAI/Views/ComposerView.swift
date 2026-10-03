import PhotosUI
import SwiftUI

struct ComposerView: View {
    @ObservedObject var model: ChatViewModel
    @ObservedObject var recorder: AudioRecorder
    @EnvironmentObject private var settings: AppSettings

    var onSend: () -> Void
    var onStop: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if recorder.isRecording { recordingBar }
            if !model.pendingAttachments.isEmpty { attachmentRow }
            if model.isAnalyzing { analyzingRow }

            HStack(alignment: .bottom, spacing: 8) {
                attachMenu

                TextField("Message Kocharian AI…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($fieldFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if model.isResponding {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                    }
                } else if model.draft.isEmpty && model.pendingAttachments.isEmpty {
                    Button {
                        Task {
                            if recorder.isRecording {
                                await finishRecording()
                            } else {
                                await recorder.start()
                            }
                        }
                    } label: {
                        Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(recorder.isRecording ? Color.red : Theme.accent)
                    }
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(model.canSend ? Theme.accent : Color.secondary)
                    }
                    .disabled(!model.canSend)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, _ in Task { await importPhoto() } }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.image, .audio, .pdf, .plainText, .json, .sourceCode, .data],
                      allowsMultipleSelection: true) { result in
            Task { await importFiles(result) }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { data in
                Task { await importCamera(data) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Pieces

    private var attachMenu: some View {
        Menu {
            Button { showPhotoPicker = true } label: {
                Label("Photo library", systemImage: "photo.on.rectangle")
            }
            Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
            Button { showFileImporter = true } label: { Label("Files", systemImage: "folder") }
            Button {
                Task { await recorder.start() }
            } label: { Label("Record audio", systemImage: "mic") }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }

    private var attachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.pendingAttachments) { attachment in
                    Chip(systemImage: attachment.kind.symbol,
                         title: attachment.name,
                         onRemove: { model.removeAttachment(attachment.id) })
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var analyzingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading the attachment on-device…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 9, height: 9)
            Text(timeString(recorder.elapsed))
                .font(.caption.monospacedDigit())
            WaveformView(level: recorder.level)
                .frame(height: 18)
            Button("Cancel") { recorder.cancel() }
                .font(.caption)
            Button {
                Task { await finishRecording() }
            } label: {
                Text("Use").font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private func timeString(_ value: TimeInterval) -> String {
        String(format: "%01d:%02d", Int(value) / 60, Int(value) % 60)
    }

    // MARK: - Imports

    private func finishRecording() async {
        guard let url = recorder.stop() else { return }
        model.isAnalyzing = true
        defer { model.isAnalyzing = false }
        do {
            let attachment = try await AttachmentService.makeAudioAttachment(
                url: url,
                name: "Voice note.m4a",
                onDevicePreferred: settings.preferOnDeviceSpeech)
            model.add(attachment)
        } catch {
            model.errorBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func importPhoto() async {
        guard let photoItem else { return }
        model.isAnalyzing = true
        defer { model.isAnalyzing = false; self.photoItem = nil }
        guard let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
        let attachment = await AttachmentService.makeImageAttachment(data: data, name: "Photo.jpg")
        model.add(attachment)
    }

    private func importCamera(_ data: Data) async {
        model.isAnalyzing = true
        defer { model.isAnalyzing = false }
        let attachment = await AttachmentService.makeImageAttachment(data: data, name: "Camera.jpg")
        model.add(attachment)
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result else { return }
        model.isAnalyzing = true
        defer { model.isAnalyzing = false }
        for url in urls {
            do {
                let attachment = try await AttachmentService.makeDocumentAttachment(url: url)
                model.add(attachment)
            } catch {
                model.errorBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// Live microphone level, drawn as a tiny bar chart.
struct WaveformView: View {
    let level: Double
    @State private var history: [Double] = Array(repeating: 0.05, count: 28)

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(Theme.accent.opacity(0.8))
                        .frame(height: max(2, geometry.size.height * value))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .onChange(of: level) { _, newValue in
            history.removeFirst()
            history.append(max(0.05, newValue))
        }
    }
}
