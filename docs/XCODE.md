# Kocharian AI for iPhone — open in Xcode and install

`ios/KocharianAI.xcodeproj` is a **100 % native Swift app**. No web view, no
JavaScript, no embedded browser — SwiftUI screens, Swift concurrency, and
Apple's own on-device frameworks:

| Feature | Framework |
|---|---|
| Chat answers | **FoundationModels** — Apple's on-device LLM (iOS 26+) |
| Chat answers (fallback / bigger model) | Your Kocharian server running Qwen 1.5B Q4_K_M, over SSE |
| Reading text in photos | **Vision** (`VNRecognizeTextRequest`) |
| Voice notes → text | **Speech** (`SFSpeechRecognizer`, on-device when supported) |
| Documents | **PDFKit** |
| Recording | **AVFoundation** |
| Storage | `Codable` JSON in the app container |

Everything stays on the phone (or on your own computer, if you choose the
server engine).

## 1. Open it

```bash
git clone https://github.com/engineer2025-sudo/Kocharian-AI.git
cd Kocharian-AI
open ios/KocharianAI.xcodeproj
```

Needs macOS with **Xcode 16 or later**. Deployment target is iOS 16; the
on-device Apple Intelligence engine lights up on iOS 26+ devices.

## 2. Signing (free Apple ID works)

1. Select the blue **KocharianAI** project → target **KocharianAI** →
   **Signing & Capabilities**.
2. Tick *Automatically manage signing* and pick your **Team**
   (add your Apple ID in Xcode ▸ Settings ▸ Accounts).
3. If the bundle id is taken, change `com.kocharian.ai` →
   `com.yourname.kocharian`.

## 3. Run on the phone

1. iPhone: **Settings ▸ Privacy & Security ▸ Developer Mode → On**, reboot.
2. Plug the phone in, select it in Xcode's device menu, press **⌘R**.
3. First install only: **Settings ▸ General ▸ VPN & Device Management ▸
   your Apple ID ▸ Trust**.

Free-account provisioning expires after 7 days — press Run again to refresh.

## 4. Pick the engine (Settings ▸ Model)

* **On-device** — zero setup on an Apple Intelligence iPhone (15 Pro and newer,
  iOS 26+, Apple Intelligence enabled). Fully offline, airplane-mode friendly.
* **Server** — start the repo's Node server on your computer:

  ```bash
  npm install && npm start      # first run downloads Qwen 1.5B Q4_K_M (~1.1 GB)
  ```

  Enter the LAN address it prints (e.g. `192.168.1.42:3000`) and tap
  **Test connection**. Phone and computer must share one Wi-Fi network;
  `NSAllowsLocalNetworking` is already set, so plain HTTP on the LAN is allowed.

## What's in the app

```
ios/KocharianAI/
├── KocharianAIApp.swift          @main, injects the stores
├── Models/
│   ├── ChatModels.swift          Conversation, ChatMessage, Attachment (Codable)
│   ├── ChatStore.swift           persistence, search, pin, rename, truncate
│   ├── ChatViewModel.swift       send / stop / regenerate / edit-and-resend
│   └── AppSettings.swift         engine, server URL, temperature, system prompt
├── Engines/
│   ├── ChatEngine.swift          protocol + EngineRouter
│   ├── AppleIntelligenceEngine.swift   FoundationModels streaming
│   └── KocharianServerEngine.swift     SSE client for /api/chat
├── Services/
│   ├── AttachmentService.swift   Vision OCR · Speech · PDFKit
│   └── AudioRecorder.swift       AVAudioRecorder + level meter
└── Views/                        SwiftUI: chat, composer, sidebar, settings,
                                  Markdown + code blocks, camera picker
```

Features: streaming token-by-token answers, stop, regenerate, edit & resend,
copy, swipe to pin/rename/delete, chat search, Markdown rendering with
copyable code blocks, Share-sheet export to Markdown, photo/camera/file/voice
attachments with on-device text extraction, light & dark mode, iPad split view.

### Adding a Swift file

The project file is generated, so after adding or deleting sources run:

```bash
python3 scripts/gen-ios-project.py
```

(It rebuilds `project.pbxproj` and the shared scheme from the folder tree.)

### App icon

`python3 scripts/make-icons.py` regenerates both the iOS asset-catalog icon and
the web icons in `public/icons/`.

---

## Don't have a Mac?

The web app is also an installable PWA: run `npm start`, open the LAN URL in
Safari on the iPhone, then Share ⬆ → **Add to Home Screen**. Android Chrome:
⋮ → **Install app**.
