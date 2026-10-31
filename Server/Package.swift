// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebcamServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),
        .package(path: "../WebcamKit"),
    ],
    targets: [
        .executableTarget(
            name: "WebcamServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "WebcamKit", package: "WebcamKit"),
            ],
            resources: [.copy("Resources/seed.json")]
        ),
        .testTarget(
            name: "WebcamServerTests",
            dependencies: [
                .target(name: "WebcamServer"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
