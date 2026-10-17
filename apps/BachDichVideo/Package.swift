// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "BachDichCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "BachDichCore", targets: ["BachDichCore"])],
    targets: [
        .target(name: "BachDichCore", path: "Shared",
                exclude: ["SharedStore.swift", "APIKeyStore.swift", "GeminiTranslator.swift"],
                sources: ["Models.swift", "TranslationPolicy.swift", "BridgeProtocol.swift", "BridgeClient.swift", "LocalHTTPServer.swift"]),
        .testTarget(name: "BachDichCoreTests", dependencies: ["BachDichCore"], path: "Tests")
    ])
