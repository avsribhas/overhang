// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Overhang",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Overhang", targets: ["Overhang"]),
    ],
    targets: [
        // Pure Foundation logic (parsers, math, formatting). No AppKit, so it is unit-testable anywhere.
        .target(name: "OverhangCore", path: "Sources/OverhangCore"),
        .executableTarget(
            name: "Overhang",
            dependencies: ["OverhangCore"],
            path: "Sources/Overhang"
        ),
        .testTarget(
            name: "OverhangCoreTests",
            dependencies: ["OverhangCore"],
            path: "Tests/OverhangCoreTests"
        ),
    ]
)
