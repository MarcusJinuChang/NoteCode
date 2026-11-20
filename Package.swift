// swift-tools-version: 6.2
//
//  Package.swift
//  NoteCode
//
//  A test-only package: it compiles the parser and formatter in
//  NoteCode/Text/Core where they are, under the module name NoteCode, so the
//  pure tests run with `swift test` on the Mac in seconds (scripts/core-test.sh;
//  docs/refactor/T11-core-package.md, option B).
//
//  The app does not depend on this, the Xcode project does not know it exists,
//  and nothing is `public`: the tests use `@testable import NoteCode`, as they
//  do in the app's test bundle. The same files run in both places, so they
//  cannot drift. A file in Text/Core that needs UIKit, or any type outside the
//  folder and the two files listed below, fails to compile here: that is the
//  boundary, enforced by the compiler.
//
//  The settings repeat the app's and the test bundle's (SWIFT_VERSION 5.0,
//  approachable concurrency, member import visibility, and default actor
//  isolation MainActor for the app only), or this would build something other
//  than what ships.
//

import Foundation
import PackageDescription

/// Everything under `root` that is not one of `keep` (paths relative to
/// `root`), as exclusions for a target whose `path` is `root`, so SwiftPM does
/// not warn about the app's other files being unhandled. A folder that holds
/// something kept is walked; any other entry is listed whole.
func exclusions(of root: String, keeping keep: [String]) -> [String] {
    let fm = FileManager.default
    // The manifest's own folder, since SwiftPM does not run it from there.
    let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
    func walk(_ dir: String) -> [String] {
        let here = base + "/" + root + (dir.isEmpty ? "" : "/" + dir)
        var out: [String] = []
        for name in ((try? fm.contentsOfDirectory(atPath: here)) ?? []).sorted() {
            let rel = dir.isEmpty ? name : dir + "/" + name
            if keep.contains(rel) { continue }
            if keep.contains(where: { $0.hasPrefix(rel + "/") }) {
                out += walk(rel)
            } else {
                out.append(rel)
            }
        }
        return out
    }
    return walk("")
}

let testSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility"),
    // SWIFT_APPROACHABLE_CONCURRENCY = YES is these five.
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

// The app target also isolates to the main actor by default; the test target
// does not.
let appSettings = testSettings + [.defaultIsolation(MainActor.self)]

let coreSources = [
    "Text/Core",
    // The two files outside Core that Core calls (the formula check asks
    // SwiftMath whether a formula parses; the cache is Foundation only).
    "Formula/FormulaValidity.swift",
    "Shared/BoundedCache.swift",
]

let testSources = [
    "Text/Core",
    "TestSupport/Tags.swift",
    "TestSupport/TopLevelSpans.swift",
]

/// Test files in Text/Core that read app code (`DebugFixture`). They run in
/// the app's test bundle only.
let appOnlyTests = [
    "Text/Core/DocumentParserSnapshotTests.swift",
    "Text/Core/InlineParserSnapshotTests.swift",
]

let package = Package(
    name: "NoteCodeCore",
    platforms: [.macOS("27.0")],
    products: [],
    dependencies: [
        // The version the app resolves.
        .package(url: "https://github.com/mgriebling/SwiftMath.git", exact: "1.7.3"),
    ],
    targets: [
        .target(
            name: "NoteCode",
            dependencies: [.product(name: "SwiftMath", package: "SwiftMath")],
            path: "NoteCode",
            exclude: exclusions(of: "NoteCode", keeping: coreSources),
            sources: coreSources,
            swiftSettings: appSettings
        ),
        .testTarget(
            name: "NoteCodeCoreTests",
            dependencies: ["NoteCode"],
            path: "NoteCodeTests",
            exclude: exclusions(of: "NoteCodeTests", keeping: testSources) + appOnlyTests,
            sources: testSources,
            swiftSettings: testSettings
        ),
    ],
    swiftLanguageModes: [.v5]
)
