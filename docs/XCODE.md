# Open in Xcode and install on your iPhone

Kocharian AI is a pure Swift iOS app — the repository contains nothing but
Swift sources, the asset catalog, `Info.plist` and the Xcode project.

## 1. Requirements

* A Mac with **Xcode 16 or later**
* An iPhone or iPad on **iOS 16+** (the on-device Apple Intelligence engine
  needs iOS 26+ on a supported device)
* An Apple ID — the **free** one works

## 2. Open the project

```bash
git clone https://github.com/engineer2025-sudo/Kocharian-AI.git
cd Kocharian-AI
open KocharianAI.xcodeproj
```

(Or Xcode ▸ File ▸ Open… and select `KocharianAI.xcodeproj` in the repo root.)

## 3. Set signing

1. Click the blue **KocharianAI** project in the navigator.
2. Select the **KocharianAI** target → **Signing & Capabilities**.
3. Tick **Automatically manage signing**.
4. **Team** → choose your Apple ID (add it under Xcode ▸ Settings ▸ Accounts ▸ +).
5. If Xcode says the bundle identifier is unavailable, change
   `com.kocharian.ai` to something unique such as `com.yourname.kocharian`.

## 4. Run on the device

1. iPhone: **Settings ▸ Privacy & Security ▸ Developer Mode → On** (iOS 16+),
   then restart the phone.
2. Connect the iPhone by cable (or Window ▸ Devices and Simulators ▸
   *Connect via network*).
3. Pick the device in the toolbar's run destination menu and press **⌘R**.
4. First install only: on the phone open
   **Settings ▸ General ▸ VPN & Device Management ▸ your Apple ID ▸ Trust**,
   then launch the app again.

Free provisioning profiles expire after **7 days** — press Run again to renew.
A paid Apple Developer account extends this to a year and unlocks TestFlight.

## 5. Choose how it answers — Settings ▸ Model

### On-device (recommended, zero setup)

Uses Apple's **FoundationModels** framework. Requires iOS 26 or later on an
Apple Intelligence capable device with Apple Intelligence enabled. Works in
airplane mode. If the device isn't eligible, the Settings screen tells you why.

### Local LLM server (any model you like, e.g. Qwen 1.5B Q4_K_M)

Run an OpenAI-compatible server on a computer on the same Wi-Fi:

```bash
# llama.cpp
llama-server -m qwen2.5-1.5b-instruct-q4_k_m.gguf --host 0.0.0.0 --port 8080

# or LM Studio  → enable the local server
# or Ollama     → http://<mac>.local:11434/v1
```

In the app: **Settings ▸ Server**, enter `http://192.168.1.42:8080`
(the model name and API key fields are optional), then **Test connection**.

Permissions the app may ask for: microphone (voice notes), speech recognition
(transcripts), camera / photo library (image attachments), local network
(server engine). All are declared in `KocharianAI/Info.plist`.

## 6. Developing

| Task | Command |
|---|---|
| Added/removed a `.swift` file | `swift Tools/GenerateProject.swift` |
| Changed the icon artwork | `swift Tools/GenerateIcons.swift` |
| Build from the command line | `xcodebuild -project KocharianAI.xcodeproj -scheme KocharianAI -sdk iphonesimulator build` |

`Tools/GenerateProject.swift` rebuilds `project.pbxproj` and the shared scheme
from the contents of `KocharianAI/`, with stable MD5-derived object ids — so
you never have to hand-edit the project file or resolve merge conflicts in it.

## Troubleshooting

* **“Untrusted Developer”** — step 4.4 above.
* **“Unable to install … device not eligible”** — enable Developer Mode.
* **Chat says Apple Intelligence is unavailable** — the device or OS doesn't
  support it; switch to the *Server* engine.
* **Server engine can't connect** — check both devices are on the same Wi-Fi,
  that the server listens on `0.0.0.0` (not `127.0.0.1`), and that the Mac
  firewall allows incoming connections on that port.
* **Voice notes come back empty** — Settings ▸ Kocharian AI ▸ Speech
  Recognition must be allowed; the first on-device model download needs Wi-Fi.
