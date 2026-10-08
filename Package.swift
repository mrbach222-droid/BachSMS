// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "BachSMSImportRegression",
    platforms: [.macOS(.v12)],
    dependencies: [.package(url: "https://github.com/CoreOffice/CoreXLSX.git", exact: "0.14.2")],
    targets: [
        .target(name: "RecipientImport", dependencies: [.product(name: "CoreXLSX", package: "CoreXLSX")],
                path: "BachSMS/App",
                exclude: ["BachSMSApp.swift", "NativePresentation.swift", "MessageTemplates.swift", "Info.plist", "Assets.xcassets"],
                sources: ["RecipientImport.swift"]),
        .testTarget(name: "RecipientImportTests", dependencies: ["RecipientImport"],
                    path: "Tests", resources: [.copy("Fixtures")])
    ]
)
