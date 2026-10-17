// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "note4meet",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "note4meet",
            path: "Sources/note4meet"
        )
    ]
)
