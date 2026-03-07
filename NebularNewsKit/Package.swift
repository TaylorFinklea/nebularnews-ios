// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "NebularNewsKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "NebularNewsKit", targets: ["NebularNewsKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "9.1.2")
        // Phase 2: Add swift-readability for article content extraction
        // .package(url: "https://github.com/Ryu0118/swift-readability", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "NebularNewsKit",
            dependencies: [
                "FeedKit"
            ]
        ),
        .testTarget(
            name: "NebularNewsKitTests",
            dependencies: ["NebularNewsKit"]
        )
    ]
)
