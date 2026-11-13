// swift-tools-version:6.0
import PackageDescription

// The plain logic of PL DEV: no UIKit, no SwiftUI, no network. It compiles and is tested on Linux
// in CI (logic.yml); the app and its extensions compile the same source files directly.
let package = Package(
    name: "PLDevCore",
    products: [.library(name: "PLDevCore", targets: ["PLDevCore"])],
    targets: [
        .target(name: "PLDevCore"),
        .testTarget(name: "PLDevCoreTests", dependencies: ["PLDevCore"]),
    ]
)
