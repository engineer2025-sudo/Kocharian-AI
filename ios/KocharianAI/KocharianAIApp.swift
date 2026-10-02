import SwiftUI
import UIKit

/// Kocharian AI — a thin native shell around the local Kocharian AI server.
///
/// The app itself contains no model: it connects to the Kocharian AI server
/// running on your computer (`npm start`) over your Wi-Fi network, so every
/// chat, image and audio file still stays on hardware you own.
@main
struct KocharianAIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(nil)
        }
    }
}

/// Shake the device to re-open the server settings sheet.
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}
