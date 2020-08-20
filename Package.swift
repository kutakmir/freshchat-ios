// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FreshchatSDK",
    products: [
        .library(
            name: "FreshchatSDK",
            targets: ["FreshchatSDK"])
    ],
    targets: [
        .target(
            name: "FreshchatSDK",
            dependencies: [],
            path: ".",
            publicHeadersPath: "include"
        )
    ]
)
