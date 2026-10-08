// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Hoardless",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hoardless", targets: ["Hoardless"]),
        .executable(name: "hoardless-cli", targets: ["hoardless-cli"]),
    ],
    targets: [
        // Rules, path safety and read-only scanning. No UI, no file changes.
        .target(name: "HoardlessCore", resources: [.copy("Resources/rules")]),
        .executableTarget(name: "Hoardless", dependencies: ["HoardlessCore"]),
        // Prints a scan as JSON; used to check the app's numbers against du.
        .executableTarget(name: "hoardless-cli", dependencies: ["HoardlessCore"]),
        .testTarget(name: "HoardlessCoreTests", dependencies: ["HoardlessCore"]),
    ],
    swiftLanguageModes: [.v5]
)
