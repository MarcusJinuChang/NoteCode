// swift-tools-version: 6.0
import PackageDescription

// A scratch package for docs/design/latex.md: renders formulas with
// SwiftMath and measures them. Nothing here is in NoteCode.xcodeproj.
let package = Package(
    name: "LaTeXSpike",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/mgriebling/SwiftMath.git", exact: "1.7.3"),
    ],
    targets: [
        .target(name: "Spike", dependencies: [.product(name: "SwiftMath", package: "SwiftMath")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SpikeTests", dependencies: ["Spike"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
