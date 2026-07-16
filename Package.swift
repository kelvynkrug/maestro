// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Maestro",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(name: "MaestroEngine", path: "Sources/MaestroEngine"),
        .executableTarget(
            name: "MaestroApp",
            dependencies: [
                "MaestroEngine",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MaestroApp"
        ),
        .executableTarget(name: "maestro-spike", path: "Sources/maestro-spike"),
    ]
)
