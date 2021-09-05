// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BluetoothStack",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .macCatalyst(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "BluetoothStack",
            targets: ["BluetoothStack"]),
    ],
    dependencies: [
        .package(name: "Synthesis", url: "https://github.com/brendenk1/Synthesis", .upToNextMajor(from: "2.0.0"))
    ],
    targets: [
        .target(
            name: "BluetoothStack",
            dependencies: [
                "Synthesis"
            ])
    ]
)
