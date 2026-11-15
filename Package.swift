// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "vapor-events",
    platforms: [
        .macOS("26.2"),
    ],
    products: [
        .library(name: "VaporEvents", targets: ["VaporEvents"]),
        .library(name: "VaporEventsPostgres", targets: ["VaporEventsPostgres"]),
        .library(name: "VaporEventsValkey", targets: ["VaporEventsValkey"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "5.0.0-beta.4"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.1"),
        .package(url: "https://github.com/valkey-io/valkey-swift.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
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
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "VaporEventsPostgres",
            dependencies: [
                "VaporEventsCore",
                "VaporEvents",
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "VaporEventsValkey",
            dependencies: [
                "VaporEventsCore",
                "VaporEvents",
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
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "VaporEventsPostgresTests",
            dependencies: [
                "VaporEventsCore",
                "VaporEventsPostgres",
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "VaporEventsValkeyTests",
            dependencies: [
                "VaporEventsCore",
                "VaporEventsValkey",
                .product(name: "Valkey", package: "valkey-swift"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
