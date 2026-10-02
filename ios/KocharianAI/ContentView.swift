import SwiftUI

struct ContentView: View {
    /// e.g. http://192.168.1.42:3000 — the computer running `npm start`.
    @AppStorage("serverURL") private var serverURL = ""
    @StateObject private var store = WebViewStore()
    @State private var showSetup = false
    @State private var draftURL = ""

    private var isConfigured: Bool { !serverURL.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Color(red: 0.13, green: 0.13, blue: 0.13).ignoresSafeArea()

            if isConfigured {
                WebView(store: store)
                    .ignoresSafeArea(.container, edges: .bottom)
            }

            if let message = store.errorMessage, isConfigured {
                errorOverlay(message)
            }

            if !isConfigured {
                welcome
            }
        }
        .sheet(isPresented: $showSetup) { setupSheet }
        .onAppear {
            draftURL = serverURL
            if isConfigured { store.load(serverURL) } else { showSetup = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            draftURL = serverURL
            showSetup = true
        }
    }

    // MARK: - Pieces

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 54, weight: .light))
                .foregroundColor(Color(red: 0.06, green: 0.64, blue: 0.50))
            Text("Kocharian AI")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text("Connect to the Kocharian AI server running on your computer.")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 36)
            Button("Set server address") { showSetup = true }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.06, green: 0.64, blue: 0.50))
        }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 42))
                .foregroundColor(.orange)
            Text("Can’t reach the server")
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 32)
            Text(serverURL)
                .font(.caption.monospaced())
                .foregroundColor(.white.opacity(0.5))
            HStack(spacing: 12) {
                Button("Retry") { store.load(serverURL) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.06, green: 0.64, blue: 0.50))
                Button("Change address") {
                    draftURL = serverURL
                    showSetup = true
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            Text("Tip: shake the phone any time to change the address.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.13, green: 0.13, blue: 0.13))
    }

    private var setupSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("http://192.168.1.42:3000", text: $draftURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server address")
                } footer: {
                    Text("""
                    On the computer running Kocharian AI, start the server with `npm start`. \
                    It prints a LAN address such as http://192.168.1.42:3000 — type that here. \
                    Your phone and the computer must be on the same Wi‑Fi network.
                    """)
                }

                Section {
                    Button("Connect") {
                        let cleaned = normalize(draftURL)
                        guard !cleaned.isEmpty else { return }
                        serverURL = cleaned
                        draftURL = cleaned
                        showSetup = false
                        store.load(cleaned)
                    }
                    .disabled(draftURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSetup = false }.disabled(!isConfigured)
                }
            }
        }
    }

    private func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "http://" + value
        }
        if URL(string: value)?.port == nil,
           !value.lowercased().hasPrefix("https://"),
           value.filter({ $0 == "/" }).count == 2 {
            value += ":3000"
        }
        return value
    }
}
