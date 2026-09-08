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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Nook",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Nook",
            resources: [
                .copy("Resources/NookLogo.svg"),
                .copy("Resources/NookAppIcon.svg")
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "NookTests", dependencies: ["Nook"], path: "Tests/NookTests")
    ]
)
