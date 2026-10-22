// swift-tools-version: 6.0
import PackageDescription

// architecture doc § Repository layout. BLEKit, CameraKit, LocationKit, SessionKit and
// Persistence are Foundation-only at their core; Core Bluetooth, Core Location,
// Keychain and SwiftUI code is behind `#if canImport(...)`, so the protocol
// logic and its tests also build with a plain Swift toolchain (`swift test`).
// SharedState holds the small Codable snapshots the widgets read, so widget
// extensions never link BLEKit.
var products: [Product] = [
    .library(name: "BLEKit", targets: ["BLEKit"]),
    .library(name: "CameraKit", targets: ["CameraKit"]),
    .library(name: "LocationKit", targets: ["LocationKit"]),
    .library(name: "SessionKit", targets: ["SessionKit"]),
    .library(name: "Persistence", targets: ["Persistence"]),
    .library(name: "SharedState", targets: ["SharedState"]),
]
var targets: [Target] = [
    .target(name: "BLEKit"),
    .target(name: "CameraKit", dependencies: ["BLEKit"]),
    .target(name: "LocationKit", dependencies: ["CameraKit"]),
    .target(name: "Persistence", dependencies: ["CameraKit"]),
    .target(name: "SharedState"),
    .target(name: "SessionKit", dependencies: ["BLEKit", "CameraKit", "LocationKit", "Persistence", "SharedState"]),
    .testTarget(name: "CameraKitTests", dependencies: ["CameraKit", "BLEKit"]),
    .testTarget(name: "SessionKitTests", dependencies: ["SessionKit", "CameraKit", "LocationKit", "BLEKit", "Persistence",
                                                         "SharedState"]),
]

// DesignKit is SwiftUI, which exists only on Apple platforms. Leaving it out on
// Linux lets `swift test` run the protocol and gesture tests anywhere.
#if !os(Linux)
products.insert(.library(name: "DesignKit", targets: ["DesignKit"]), at: 0)
targets.insert(.target(name: "DesignKit"), at: 0)
#endif

let package = Package(
    name: "xGRCCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: products,
    targets: targets
)
