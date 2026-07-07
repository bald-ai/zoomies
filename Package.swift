// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "zoomies",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Zoomies", targets: ["Zoomies"])
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "Zoomies",
            path: "Sources",
            exclude: [
                "Resources/.keep",
                "Resources/Zoomies.icns"
            ],
            resources: [
                .process("Resources/screenshot-sound.mp3")
            ]
        ),
        .testTarget(
            name: "ZoomiesTests",
            dependencies: ["Zoomies"],
            path: "Tests/ZoomiesTests"
        )
    ]
)
