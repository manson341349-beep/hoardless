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
        // The rule files themselves (rules/apps), bundled as they are: no copy, no link.
        .target(name: "HoardlessRules", path: "rules", exclude: ["schema.json"], resources: [.copy("apps")]),
        .target(name: "HoardlessCore", dependencies: ["HoardlessRules"]),
        .executableTarget(name: "Hoardless", dependencies: ["HoardlessCore"], resources: [.copy("Resources/Art")]),
        // Prints a scan as JSON; used to check the app's numbers against du.
        .executableTarget(name: "hoardless-cli", dependencies: ["HoardlessCore"]),
        .testTarget(name: "HoardlessCoreTests", dependencies: ["HoardlessCore"]),
    ],
    swiftLanguageModes: [.v5]
)
