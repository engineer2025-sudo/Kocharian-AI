# Open in Xcode, add the engine, install on your iPhone

Kocharian AI is a pure Swift iOS app with **two ways to answer**:

1. **Apple Intelligence** — Apple's built-in model via `FoundationModels`.
   Nothing to download. Needs iOS 26+ on an Apple Intelligence device.
2. **On-board model** — a GGUF you download inside the app
   (**Qwen 2.5 1.5B Instruct Q4_K_M**, Qwen 2.5 Coder 1.5B, Qwen 2.5 0.5B,
   SmolLM2 360M/135M, or your own `.gguf`), run locally with llama.cpp.

There is **no server mode** — the app never talks to a backend. The only
network use is downloading a model you pick.

---

## 1. Open the project

```bash
git clone -b arena/01a0fec4-kocharian-ai https://github.com/engineer2025-sudo/Kocharian-AI.git
cd Kocharian-AI
open KocharianAI.xcodeproj
```

Requires macOS with **Xcode 16+**. Deployment target: iOS 17
(Apple Intelligence engine lights up on iOS 26+).

## 2. Let Xcode fetch the engine (automatic)

Nothing to build by hand. The project references a local Swift package,
`Packages/LlamaFramework`, which points at the **official llama.cpp XCFramework
release** (`b11200`, ~61 MB). The first time you open or build the project,
Xcode downloads and links it automatically — watch the status bar for
*“Resolve Package Graph”*. You need internet for that one download only.

To move to a newer llama.cpp build, edit `Packages/LlamaFramework/Package.swift`
and change `version` + `checksum` (the checksum is the `sha256` digest GitHub
shows for the `llama-bXXXXX-xcframework.zip` asset).

If package resolution ever gets stuck: **File ▸ Packages ▸ Reset Package Caches**.

## 3. Signing

1. Blue **KocharianAI** project → target **KocharianAI** →
   **Signing & Capabilities**.
2. Tick *Automatically manage signing*, pick your **Team** (free Apple ID is
   fine; add it in Xcode ▸ Settings ▸ Accounts).
3. Change the bundle id `com.kocharian.ai` if Xcode says it's taken.
4. The target ships `KocharianAI.entitlements` with
   `com.apple.developer.kernel.increased-memory-limit` so a 1.5B model has room
   to run. With a **free** account that entitlement isn't allowed — if signing
   fails, clear **Build Settings ▸ Code Signing Entitlements** (the app still
   runs; just prefer the 0.5B model on smaller devices).

## 4. Run

1. iPhone: **Settings ▸ Privacy & Security ▸ Developer Mode → On**, reboot.
2. Plug in, pick the device in Xcode's toolbar, press **⌘R**.
3. First install: iPhone **Settings ▸ General ▸ VPN & Device Management ▸ your
   Apple ID ▸ Trust**.

Free provisioning expires after 7 days — run again to renew.

## 5. Get a model (in the app)

**⋯ menu ▸ Models**, or **Settings ▸ On-board model ▸ Model**:

| Model | Size | Good for |
|---|---|---|
| Qwen 2.5 1.5B Instruct Q4_K_M | ~1.1 GB | recommended, best quality |
| Qwen 2.5 Coder 1.5B Q4_K_M | ~1.1 GB | code questions |
| Qwen 2.5 0.5B Instruct Q4_K_M | ~400 MB | older / 4 GB devices |
| SmolLM2 360M Q8_0 | ~390 MB | very fast, simple answers |
| SmolLM2 135M Q8_0 | ~145 MB | smallest |

Tap **Get** to download (pause/resume supported, progress shown), then tap the
model to select it. **Import .gguf** in the toolbar adds any file from the
Files app. Swipe a model to delete it. Downloads are stored in the app's
Application Support folder and excluded from iCloud backup.

Memory guide: a 1.5B Q4_K_M needs roughly **2 GB free RAM** while answering —
comfortable on iPhone 15 Pro / 16 and newer, tight on 4 GB devices (use 0.5B).

## 6. Switch engines

**Settings ▸ Answers come from**: *Apple* or *On-board*. The chat screen shows
a banner with a **Get a model** shortcut whenever the selected engine isn't
ready yet.

## Developing

| Task | Command |
|---|---|
| Added/removed a `.swift` file | `swift Tools/GenerateProject.swift` |
| Changed the icon artwork | `swift Tools/GenerateIcons.swift` |
| CLI build | `xcodebuild -project KocharianAI.xcodeproj -scheme KocharianAI -sdk iphonesimulator build` |

## Troubleshooting

* **“The llama.cpp framework isn’t linked yet.”** — package resolution failed; File ▸ Packages ▸ Reset Package Caches, then build again.
* **Download stops at a few KB** — the Hugging Face URL redirected to an error
  page; check Wi-Fi, then retry. Any direct `.gguf` link works via *Import*.
* **App is killed while answering** — the model is too large for the device:
  pick a smaller one or lower *Max new tokens* / context.
* **Apple engine says unavailable** — needs iOS 26+, an Apple Intelligence
  capable device, and Apple Intelligence switched on in iOS Settings.
* **Voice notes empty** — allow Speech Recognition in iOS Settings for the app.
