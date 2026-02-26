// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Toodoos",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Toodoos",
            path: "Sources/Toodoos",
            linkerSettings: [
                .unsafeFlags(["-framework", "Carbon"])
            ]
        )
    ]
)
