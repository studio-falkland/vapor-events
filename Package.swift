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
        .library(name: "VaporEventsValkey", targets: ["VaporEventsValkey"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.3"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.1"),
        .package(url: "https://github.com/valkey-io/valkey-swift.git", from: "1.6.0"),
        .package(url: "https://github.com/vapor/queues.git", from: "1.0.0"),
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
                .product(name: "Queues", package: "queues"),
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
        .target(
            name: "VaporEventsValkey",
            dependencies: [
                "VaporEventsCore",
                "VaporEvents",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Valkey", package: "valkey-swift"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "VaporEventsCoreTests",
            dependencies: ["VaporEventsCore"]
        ),
        .testTarget(
            name: "VaporEventsTests",
            dependencies: [
                "VaporEvents",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "XCTQueues", package: "queues"),
            ]
        ),
        .testTarget(
            name: "VaporEventsPostgresTests",
            dependencies: ["VaporEventsPostgres"]
        ),
        .testTarget(
            name: "VaporEventsValkeyTests",
            dependencies: [
                "VaporEventsValkey",
                .product(name: "Valkey", package: "valkey-swift"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
