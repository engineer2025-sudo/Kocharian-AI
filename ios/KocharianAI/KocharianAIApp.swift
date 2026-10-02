import SwiftUI

/// Kocharian AI — a fully native SwiftUI chat app.
///
/// * Answers come from Apple's on-device foundation model (iOS 26+), or from
///   the Kocharian AI server running the Qwen 1.5B GGUF model on your computer.
/// * Photos are read with Vision OCR, voice notes with the Speech framework,
///   documents with PDFKit — all on the device.
@main
struct KocharianAIApp: App {
    @StateObject private var store = ChatStore()
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { store.saveNow() }
        }
    }
}
