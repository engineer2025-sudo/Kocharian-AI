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

## Two engines (Settings ▸ Model)

| Engine | What it is | Requirements |
|---|---|---|
| **On-device** | Apple's foundation model through **FoundationModels** | iOS 26+, Apple Intelligence capable device. Fully offline. |
| **Local LLM server** | Any OpenAI-compatible endpoint you host, e.g. Qwen 1.5B Instruct Q4_K_M | A computer on the same Wi-Fi |

Example for the second one — llama.cpp on your Mac/PC:

```bash
llama-server -m qwen2.5-1.5b-instruct-q4_k_m.gguf --host 0.0.0.0 --port 8080
```

then enter `http://192.168.1.42:8080` in Settings ▸ Server and tap
**Test connection**. LM Studio, Ollama (`http://mac.local:11434/v1`) and vLLM
work the same way. `NSAllowsLocalNetworking` is set, so plain HTTP on your LAN
is allowed; nothing is ever sent to a third-party cloud.

## Project layout

```
KocharianAI.xcodeproj
KocharianAI/
├── KocharianAIApp.swift              @main
├── Models/      ChatModels · ChatStore · ChatViewModel · AppSettings
├── Engines/     ChatEngine (protocol + router)
│                AppleIntelligenceEngine · LocalLLMEngine
├── Services/    AttachmentService (Vision · Speech · PDFKit) · AudioRecorder
├── Views/       RootView · ConversationListView · ChatView · ComposerView
│                MessageRow · MarkdownText · SettingsView · CameraPicker · Theme
├── Assets.xcassets
└── Info.plist
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

Chats, photos, recordings and documents are processed on the device, or on a
machine you own and point the app at. There is no analytics, no account and no
third-party network call.

> The earlier Node/web prototype of Kocharian AI lives in this repository's git
> history (before the “all-Swift iOS app” commit) if you ever need it.
