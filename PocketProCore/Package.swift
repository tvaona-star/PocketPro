// swift-tools-version: 5.9
// PocketProCore — platform-agnostic bowling domain logic (PRD 8.1/8.2).
// No UIKit/SwiftUI/SwiftData imports. This package is the Android porting spec.
import PackageDescription

let package = Package(
    name: "PocketProCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "PocketProCore", targets: ["PocketProCore"]),
    ],
    targets: [
        .target(name: "PocketProCore"),
        .testTarget(name: "PocketProCoreTests", dependencies: ["PocketProCore"]),
    ]
)
