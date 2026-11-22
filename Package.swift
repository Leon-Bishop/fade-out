// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FadeOutCore",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "FadeOutAudio", targets: ["FadeOutAudio"]),
        .executable(name: "FadeOutHarness", targets: ["FadeOutHarness"])
    ],
    targets: [
        .target(name: "FadeOutDSP", publicHeadersPath: "include"),
        .target(name: "FadeOutAudio", dependencies: ["FadeOutDSP"]),
        .executableTarget(name: "FadeOutHarness", dependencies: ["FadeOutAudio", "FadeOutDSP"]),
        .testTarget(name: "FadeOutAudioTests", dependencies: ["FadeOutAudio", "FadeOutDSP"])
    ]
)
