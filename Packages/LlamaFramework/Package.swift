// swift-tools-version: 5.9
//
//  LlamaFramework
//
//  Wraps the official llama.cpp XCFramework release so Xcode downloads and
//  links it automatically — nothing to build by hand. Bump `version` and
//  `checksum` together to move to a newer llama.cpp build; the checksum is the
//  `sha256` digest GitHub shows for the release asset.
//

import PackageDescription

let version = "b11200"
let checksum = "c62cae37316b12938cde3224493e008d121635bf759ddd08fbcdd587b3b8808c"

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
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/\(version)/llama-\(version)-xcframework.zip",
            checksum: checksum
        )
    ]
)
