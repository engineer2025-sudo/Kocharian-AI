import Foundation
import SwiftUI

/// A `.gguf` file that currently lives on the device.
struct InstalledModel: Identifiable, Codable, Hashable {
    var id: String
    var displayName: String
    var fileName: String
    var byteSize: Int64
    var template: PromptTemplate
    var contextSize: Int
    var installedAt: Date = Date()
    /// `true` when the user imported their own file instead of downloading one.
    var imported: Bool = false
}

struct DownloadState: Equatable {
    var received: Int64 = 0
    var expected: Int64 = 0
    var isPaused: Bool = false
    var errorText: String?

    var fraction: Double {
        expected > 0 ? min(1, Double(received) / Double(expected)) : 0
    }
}

/// Downloads, stores, imports and deletes on-board models.
@MainActor
final class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()

    @Published private(set) var installed: [InstalledModel] = []
    @Published private(set) var downloads: [String: DownloadState] = [:]
    @Published var selectedModelID: String? {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: "selectedModelID") }
    }
    @Published var lastError: String?

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.timeoutIntervalForResource = 24 * 3600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    override init() {
        super.init()
        selectedModelID = UserDefaults.standard.string(forKey: "selectedModelID")
        loadIndex()
        pruneMissingFiles()
    }

    // MARK: - Locations

    static var modelsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var folder = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true          // multi-GB files don't belong in iCloud backups
        try? folder.setResourceValues(values)
        return base
    }

    private var indexURL: URL { Self.modelsFolder.appendingPathComponent("index.json") }

    func fileURL(for model: InstalledModel) -> URL {
        Self.modelsFolder.appendingPathComponent(model.fileName)
    }

    func model(withID id: String) -> InstalledModel? {
        installed.first { $0.id == id }
    }

    var selectedModel: InstalledModel? {
        guard let selectedModelID else { return installed.first }
        return installed.first { $0.id == selectedModelID } ?? installed.first
    }

    func isInstalled(_ spec: ModelSpec) -> Bool {
        installed.contains { $0.id == spec.id }
    }

    var totalBytesOnDisk: Int64 {
        installed.reduce(0) { $0 + $1.byteSize }
    }

    static var freeDiskBytes: Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: - Downloading

    func download(_ spec: ModelSpec) {
        guard tasks[spec.id] == nil, let url = spec.url else { return }

        if Self.freeDiskBytes > 0, Self.freeDiskBytes < spec.byteSize + 300_000_000 {
            lastError = "Not enough free space for \(spec.name) (\(spec.sizeText) needed)."
            return
        }

        downloads[spec.id] = DownloadState(received: 0, expected: spec.byteSize)

        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: spec.id) {
            task = session.downloadTask(withResumeData: data)
        } else {
            var request = URLRequest(url: url)
            request.setValue("KocharianAI/1.0", forHTTPHeaderField: "User-Agent")
            task = session.downloadTask(with: request)
        }
        task.taskDescription = spec.id
        tasks[spec.id] = task
        task.resume()
    }

    func pause(_ spec: ModelSpec) {
        guard let task = tasks[spec.id] else { return }
        task.cancel { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.resumeData[spec.id] = data }
                self.tasks[spec.id] = nil
                self.downloads[spec.id]?.isPaused = true
            }
        }
    }

    func cancel(_ spec: ModelSpec) {
        tasks[spec.id]?.cancel()
        tasks[spec.id] = nil
        resumeData[spec.id] = nil
        downloads[spec.id] = nil
    }

    func isDownloading(_ spec: ModelSpec) -> Bool {
        downloads[spec.id] != nil && downloads[spec.id]?.isPaused == false
    }

    // MARK: - Import / delete

    /// Adds a `.gguf` the user picked in the Files app.
    func importModel(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.deletingPathExtension().lastPathComponent
        let fileName = UUID().uuidString.prefix(8) + "-" + url.lastPathComponent
        let destination = Self.modelsFolder.appendingPathComponent(String(fileName))
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let model = InstalledModel(id: "imported-" + String(fileName),
                                       displayName: name,
                                       fileName: String(fileName),
                                       byteSize: size,
                                       template: Self.guessTemplate(from: name),
                                       contextSize: 4096,
                                       imported: true)
            installed.append(model)
            if selectedModelID == nil { selectedModelID = model.id }
            saveIndex()
        } catch {
            lastError = "Couldn’t import that file: \(error.localizedDescription)"
        }
    }

    func delete(_ model: InstalledModel) {
        try? FileManager.default.removeItem(at: fileURL(for: model))
        installed.removeAll { $0.id == model.id }
        if selectedModelID == model.id { selectedModelID = installed.first?.id }
        saveIndex()
        NotificationCenter.default.post(name: .onboardModelChanged, object: nil)
    }

    private static func guessTemplate(from name: String) -> PromptTemplate {
        let lower = name.lowercased()
        if lower.contains("llama-3") || lower.contains("llama3") { return .llama3 }
        if lower.contains("gemma") { return .gemma }
        return .chatML
    }

    // MARK: - Index persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        installed = (try? decoder.decode([InstalledModel].self, from: data)) ?? []
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(installed) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func pruneMissingFiles() {
        let before = installed.count
        installed.removeAll { !FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        if installed.count != before { saveIndex() }
        if let id = selectedModelID, !installed.contains(where: { $0.id == id }) {
            selectedModelID = installed.first?.id
        }
    }

    fileprivate func finishDownload(id: String, tempURL: URL) {
        guard let spec = ModelCatalog.spec(id: id) else { return }
        let destination = Self.modelsFolder.appendingPathComponent(spec.fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                ?? spec.byteSize

            guard size > 1_000_000 else {           // an HTML error page, not a model
                try? FileManager.default.removeItem(at: destination)
                downloads[id]?.errorText = "The download didn’t contain a model file."
                return
            }

            installed.removeAll { $0.id == spec.id }
            installed.append(InstalledModel(id: spec.id,
                                            displayName: spec.name,
                                            fileName: spec.fileName,
                                            byteSize: size,
                                            template: spec.template,
                                            contextSize: spec.recommendedContext))
            saveIndex()
            downloads[id] = nil
            tasks[id] = nil
            if selectedModelID == nil { selectedModelID = spec.id }
            NotificationCenter.default.post(name: .onboardModelChanged, object: nil)
        } catch {
            downloads[id]?.errorText = error.localizedDescription
        }
    }

    fileprivate func updateProgress(id: String, received: Int64, expected: Int64) {
        var state = downloads[id] ?? DownloadState()
        state.received = received
        if expected > 0 { state.expected = expected }
        state.isPaused = false
        downloads[id] = state
    }

    fileprivate func failDownload(id: String, message: String?) {
        tasks[id] = nil
        guard let message else { return }          // nil = cancelled on purpose
        var state = downloads[id] ?? DownloadState()
        state.errorText = message
        downloads[id] = state
    }
}

extension Notification.Name {
    /// Posted when the selected on-board model is installed, deleted or swapped.
    static let onboardModelChanged = Notification.Name("onboardModelChanged")
}

// MARK: - URLSession delegate

extension ModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        // The temp file disappears when this method returns — move it now.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".gguf")
        try? FileManager.default.moveItem(at: location, to: staging)
        Task { @MainActor in
            ModelManager.shared.finishDownload(id: id, tempURL: staging)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in
            ModelManager.shared.updateProgress(id: id,
                                               received: totalBytesWritten,
                                               expected: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        let message: String?
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            message = error.localizedDescription
        } else {
            message = nil
        }
        Task { @MainActor in
            ModelManager.shared.failDownload(id: id, message: message)
        }
    }
}
