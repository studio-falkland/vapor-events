// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vapor-events",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "VaporEvents", targets: ["VaporEvents"]),
        .library(name: "VaporEventsPostgres", targets: ["VaporEventsPostgres"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.3"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "VaporEventsCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "VaporEvents",
            dependencies: [
                "VaporEventsCore",
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .target(
            name: "VaporEventsPostgres",
            dependencies: [
                "VaporEventsCore",
                "VaporEvents",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Logging", package: "swift-log"),
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
        .testTarget(
            name: "VaporEventsPostgresTests",
            dependencies: ["VaporEventsPostgres"]
        ),
    ]
)
