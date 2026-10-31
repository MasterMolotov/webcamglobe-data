// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebcamKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "WebcamKit", targets: ["WebcamKit"]),
    ],
    targets: [
        .target(name: "WebcamKit"),
        .testTarget(name: "WebcamKitTests", dependencies: ["WebcamKit"]),
    ]
)
