import Foundation
import PDFKit
import Speech
import UIKit
import UniformTypeIdentifiers
import Vision

/// Turns files the user attaches into plain text, entirely on-device:
/// images via Vision OCR, audio via the Speech framework, documents via PDFKit.
enum AttachmentService {

    enum Failure: LocalizedError {
        case unreadable(String)
        case speechDenied
        case speechUnavailable

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Couldn’t read “\(name)”."
            case .speechDenied: return "Speech recognition permission was denied. Enable it in Settings ▸ Kocharian AI."
            case .speechUnavailable: return "Speech recognition isn’t available on this device right now."
            }
        }
    }

    // MARK: - Storage

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func fileURL(for attachment: Attachment) -> URL? {
        guard let name = attachment.fileName else { return nil }
        return folder.appendingPathComponent(name)
    }

    @discardableResult
    static func persist(_ data: Data, preferredExtension: String) -> String? {
        let name = UUID().uuidString + "." + preferredExtension
        do {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    // MARK: - Entry points

    /// Image picked from the photo library or camera.
    static func makeImageAttachment(data: Data, name: String) async -> Attachment {
        let stored = persist(data, preferredExtension: "jpg")
        var attachment = Attachment(name: name, kind: .image, byteCount: data.count, fileName: stored)
        attachment.extractedText = (try? await recognizeText(in: data)) ?? ""
        return attachment
    }

    /// Audio recorded in-app or imported from Files.
    static func makeAudioAttachment(url: URL, name: String, onDevicePreferred: Bool) async throws -> Attachment {
        let data = (try? Data(contentsOf: url)) ?? Data()
        let stored = persist(data, preferredExtension: url.pathExtension.isEmpty ? "m4a" : url.pathExtension)
        var attachment = Attachment(name: name, kind: .audio, byteCount: data.count, fileName: stored)
        attachment.extractedText = try await transcribe(url: url, onDevicePreferred: onDevicePreferred)
        return attachment
    }

    /// Any document from the Files app.
    static func makeDocumentAttachment(url: URL) async throws -> Attachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension) ?? .data

        if type.conforms(to: .image), let data = try? Data(contentsOf: url) {
            return await makeImageAttachment(data: data, name: name)
        }
        if type.conforms(to: .audio) || type.conforms(to: .audiovisualContent) {
            return try await makeAudioAttachment(url: url, name: name, onDevicePreferred: true)
        }

        let data = (try? Data(contentsOf: url)) ?? Data()
        var attachment = Attachment(name: name, kind: .document, byteCount: data.count,
                                    fileName: persist(data, preferredExtension: url.pathExtension))

        if type.conforms(to: .pdf), let document = PDFDocument(url: url) {
            var text = ""
            for index in 0..<document.pageCount {
                if let page = document.page(at: index), let pageText = page.string {
                    text += pageText + "\n"
                }
            }
            attachment.extractedText = text
        } else if let text = String(data: data, encoding: .utf8) {
            attachment.extractedText = text
        } else {
            throw Failure.unreadable(name)
        }
        return attachment
    }

    // MARK: - Vision OCR

    static func recognizeText(in data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = UIImage(data: data), let cgImage = image.cgImage else {
                    continuation.resume(throwing: Failure.unreadable("image"))
                    return
                }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if #available(iOS 16.0, *) {
                    request.automaticallyDetectsLanguage = true
                }
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let lines = (request.results ?? []).compactMap { observation in
                        observation.topCandidates(1).first?.string
                    }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Speech

    static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        if SFSpeechRecognizer.authorizationStatus() != .notDetermined {
            return SFSpeechRecognizer.authorizationStatus()
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    static func transcribe(url: URL, onDevicePreferred: Bool) async throws -> String {
        guard await requestSpeechAuthorization() == .authorized else { throw Failure.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { throw Failure.speechUnavailable }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if onDevicePreferred, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            let box = ResumeBox()
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.finish { continuation.resume(throwing: error) }
                    return
                }
                guard let result, result.isFinal else { return }
                box.finish { continuation.resume(returning: result.bestTranscription.formattedString) }
            }
        }
    }

    /// Guards against the recognition callback firing more than once.
    private final class ResumeBox: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func finish(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }
}
