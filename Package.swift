// swift-tools-version: 6.0
import PackageDescription

// The app's shared domain and persistence sources can be tested without a simulator.
let package = Package(
    name: "ShiplogCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ShiplogCore", targets: ["Shiplog"])],
    targets: [
        .target(
            name: "Shiplog",
            path: "Shiplog",
            exclude: ["App", "Design", "Features", "Preview", "Resources"],
            sources: ["Domain", "Persistence", "Services"]
        ),
        .testTarget(name: "ShiplogTests", dependencies: ["Shiplog"], path: "ShiplogTests"),
    ]
)
