// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Yeet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Yeet", targets: ["Yeet"])
    ],
    targets: [
        .executableTarget(
            name: "Yeet",
            path: "Sources/Yeet"
        )
    ]
)
