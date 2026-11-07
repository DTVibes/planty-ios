// swift-tools-version:5.9
import PackageDescription

// PlantyKit holds Planty's domain models and rules (care engine, moods, XP).
// It imports Foundation only, so it builds and tests on macOS, iOS and Linux.
let package = Package(
    name: "PlantyKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlantyKit", targets: ["PlantyKit"])
    ],
    targets: [
        .target(name: "PlantyKit"),
        .testTarget(name: "PlantyKitTests", dependencies: ["PlantyKit"])
    ]
)
