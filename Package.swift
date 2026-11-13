// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwipeSelect",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "SwipeSelect", targets: ["SwipeSelect"]),
    ],
    targets: [
        .target(name: "SwipeSelect"),
        .testTarget(name: "SwipeSelectTests", dependencies: ["SwipeSelect"]),
    ]
)
