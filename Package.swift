// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Nook",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Nook", targets: ["Nook"])
    ],
    targets: [
        .executableTarget(
            name: "Nook",
            path: "Sources/Nook"
        )
    ]
)
