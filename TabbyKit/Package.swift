// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TabbyKit",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "TabbyKit", targets: ["TabbyKit"]),
        .executable(name: "tabby-extract", targets: ["tabby-extract"]),
    ],
    targets: [
        .target(name: "TabbyKit"),
        .executableTarget(name: "tabby-extract", dependencies: ["TabbyKit"]),
        .testTarget(
            name: "TabbyKitTests",
            dependencies: ["TabbyKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
