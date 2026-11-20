// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Drift",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Drift",
            path: "Sources/Drift",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
