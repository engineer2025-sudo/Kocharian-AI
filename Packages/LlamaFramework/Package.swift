// swift-tools-version: 5.9
//
//  LlamaFramework
//
//  Supplies the llama.cpp engine to the app in one of two ways:
//
//  1. Drop your own build at Packages/LlamaFramework/llama.xcframework
//     (produced by llama.cpp's ./build-xcframework.sh — it lands in
//     llama.cpp/build-apple/llama.xcframework) and it is used as-is.
//  2. Otherwise Xcode downloads the official pre-built XCFramework from the
//     llama.cpp GitHub release below (~61 MB, once).
//
//  Nothing else to configure either way. Bump `version` + `checksum` together
//  to move to a newer llama.cpp build; the checksum is the `sha256` digest
//  GitHub shows for the release asset.
//

import PackageDescription
import Foundation

let version = "b11200"
let checksum = "c62cae37316b12938cde3224493e008d121635bf759ddd08fbcdd587b3b8808c"

let localFramework = "llama.xcframework"
let hasLocalFramework = FileManager.default.fileExists(
    atPath: Context.packageDirectory + "/" + localFramework
)

let llamaTarget: Target = hasLocalFramework
    ? .binaryTarget(name: "llama", path: localFramework)
    : .binaryTarget(
        name: "llama",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/\(version)/llama-\(version)-xcframework.zip",
        checksum: checksum
      )

let package = Package(
    name: "LlamaFramework",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "llama", targets: ["llama"])
    ],
    targets: [llamaTarget]
)
