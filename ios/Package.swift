// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "firebase_messaging_handler",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        .library(name: "firebase-messaging-handler", targets: ["firebase_messaging_handler"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "firebase_messaging_handler",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Classes"
        ),
    ]
)
