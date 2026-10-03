# Kocharian AI — iOS app

A private, ChatGPT-style assistant for iPhone and iPad. **100 % Swift**: SwiftUI
screens, Swift concurrency, Apple's on-device frameworks. No web view, no
JavaScript, no server code in this repository.

```bash
git clone https://github.com/engineer2025-sudo/Kocharian-AI.git
cd Kocharian-AI
open KocharianAI.xcodeproj      # Xcode 16+, then press ⌘R
```

Step-by-step install guide (signing, Developer Mode, trusting the app):
[docs/XCODE.md](docs/XCODE.md).

## What it does

* **Streaming chat** — answers appear token by token, with stop, regenerate,
  edit-and-resend, copy and delete.
* **Attachments, read on-device**
  * photos & camera → **Vision** text recognition
  * voice notes → **Speech** (`SFSpeechRecognizer`, on-device when supported),
    recorded in-app with a live level meter
  * PDFs and text files → **PDFKit**
* **Conversations** — sidebar with search, pin, rename, swipe-delete; stored as
  `Codable` JSON inside the app container.
* **Markdown rendering** with copyable code blocks.
* **Export** a chat to Markdown through the share sheet.
* iPhone + iPad (split view), light & dark mode, Dynamic Type.

## Two engines (Settings ▸ Answers come from)

| Engine | What it is | Requirements |
|---|---|---|
| **Apple Intelligence** | Apple's built-in model via `FoundationModels` | iOS 26+, Apple Intelligence capable device. Nothing to download. |
| **On-board model** | A GGUF you download in the app, run with llama.cpp | ~1.1 GB free space for Qwen 2.5 1.5B (smaller models available) |

The app has **no server mode** and makes no cloud calls. The only network use
is downloading a model you choose, from the in-app **Models** screen:

| Model | Size | Notes |
|---|---|---|
| Qwen 2.5 1.5B Instruct Q4_K_M | ~1.1 GB | recommended |
| Qwen 2.5 Coder 1.5B Q4_K_M | ~1.1 GB | code |
| Qwen 2.5 0.5B Instruct Q4_K_M | ~400 MB | older devices |
| SmolLM2 360M / 135M Q8_0 | ~390 / 145 MB | tiny and fast |

Downloads can be paused and resumed, you can import your own `.gguf` from the
Files app, and deleting a model frees the space immediately.

> **No setup needed:** the on-board engine uses the official llama.cpp
> XCFramework, wired in as the local Swift package `Packages/LlamaFramework`.
> Xcode downloads and links it automatically the first time you build
> (~61 MB). See [docs/XCODE.md](docs/XCODE.md).

## Project layout

```
KocharianAI.xcodeproj
KocharianAI/
├── KocharianAIApp.swift              @main
├── Models/      ChatModels · ChatStore · ChatViewModel · AppSettings
├── Models/      … ModelCatalog · ModelManager (downloads)
├── Engines/     ChatEngine (protocol + router)
│                AppleIntelligenceEngine · OnboardModelEngine · LlamaRunner
├── Services/    AttachmentService (Vision · Speech · PDFKit) · AudioRecorder
├── Views/       RootView · ConversationListView · ChatView · ComposerView
│                MessageRow · MarkdownText · ModelsView · SettingsView
│                CameraPicker · Theme
├── Assets.xcassets
└── Info.plist
Packages/
└── LlamaFramework/Package.swift   official llama.cpp XCFramework (auto-fetched)
Tools/
├── GenerateProject.swift   regenerates the .xcodeproj from the folder tree
└── GenerateIcons.swift     draws the app icon with Core Graphics
```

Both tools are Swift scripts — run them from the repository root:

```bash
swift Tools/GenerateProject.swift    # after adding or removing a .swift file
swift Tools/GenerateIcons.swift      # after changing the icon artwork
```

## Privacy

Chats, photos, recordings and documents are processed entirely on the device.
No analytics, no account, no server. Once a model is downloaded the app works
in airplane mode.

> The earlier Node/web prototype of Kocharian AI lives in this repository's git
> history (before the “all-Swift iOS app” commit) if you ever need it.
