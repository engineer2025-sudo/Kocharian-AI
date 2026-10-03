import SwiftUI

/// Kocharian AI — a fully native SwiftUI chat app.
///
/// * Answers come from Apple's on-device foundation model (iOS 26+), or from
///   a GGUF model you download inside the app (Qwen 2.5 1.5B Instruct Q4_K_M
///   and smaller) and run locally with llama.cpp.
/// * Photos are read with Vision OCR, voice notes with the Speech framework,
///   documents with PDFKit — all on the device.
@main
struct KocharianAIApp: App {
    @StateObject private var store = ChatStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var models = ModelManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(models)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { store.saveNow() }
        }
    }
}
