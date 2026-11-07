// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vapor-events",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "VaporEvents", targets: ["VaporEvents"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.3"),
    ],
    targets: [
        .target(name: "VaporEventsCore"),
        .target(
            name: "VaporEvents",
            dependencies: [
                "VaporEventsCore",
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "VaporEventsCoreTests",
            dependencies: ["VaporEventsCore"]
        ),
        .testTarget(
            name: "VaporEventsTests",
            dependencies: ["VaporEvents"]
        ),
    ]
)
