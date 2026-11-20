//
//  AppStoreReadinessTests.swift
//  NoteCodeTests
//
//  What an upload to App Store Connect checks before a person ever sees the
//  app. Each of these would bounce an upload or raise a question in review,
//  and none of them shows up in the app itself. These hold for both
//  editions; what only the App Store edition ships (ads, tracking, the
//  policy page's Run and ads sections) is in Pro/AppStoreReadinessTests+Pro.swift.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Ready for the App Store", .tags(.library))
struct AppStoreReadinessTests {

    @Test("The manifest gives the app's own settings as its reason to read UserDefaults")
    func userDefaultsReason() throws {
        let apis = try #require(Self.privacyManifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = apis.reduce(into: [String: [String]]()) { reasons, api in
            if let type = api["NSPrivacyAccessedAPIType"] as? String {
                reasons[type] = api["NSPrivacyAccessedAPITypeReasons"] as? [String]
            }
        }

        // @AppStorage is UserDefaults, read only by this app: CA92.1.
        #expect(reasons == ["NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]])
    }

    @Test("The manifest gives a reason for every required-reason API the shipped code calls")
    func everyRequiredReasonAPIIsDeclared() throws {
        // App Store Connect scans the binary for these APIs and rejects an
        // upload whose manifest gives no reason for one. Debug/ is left out:
        // all of it is behind #if DEBUG, which an archive never compiles.
        let used = try Self.requiredReasonCategories(in: ["NoteCode", "OpenSource"], excluding: ["NoteCode/Debug"])
        let apis = try #require(Self.privacyManifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let declared = Set(apis.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })

        // @AppStorage is everywhere, so a scan that finds nothing read nothing.
        #expect(used["NSPrivacyAccessedAPICategoryUserDefaults"] != nil)
        // And the patterns find a call written the way code writes it:
        // Debug/ reads the boot clock, behind #if DEBUG.
        let debug = try Self.requiredReasonCategories(in: ["NoteCode/Debug"])
        #expect(debug["NSPrivacyAccessedAPICategorySystemBootTime"] != nil)
        for (category, places) in used where !declared.contains(category) {
            Issue.record("\(category) is used but not declared in PrivacyInfo.xcprivacy: \(places.joined(separator: ", "))")
        }
    }

    @Test("The app says it uses only exempt encryption, so uploads skip the question")
    func exemptEncryption() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool == false)
    }

    @Test("The app declares no background modes, since it uses none")
    func noBackgroundModes() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") == nil)
    }

#if os(iOS)
    @Test("The launch screen is the system background and nothing else")
    func launchScreenIsPlain() throws {
        // INFOPLIST_KEY_UILaunchScreen_Generation writes an empty
        // UILaunchScreen dictionary. A UIImageName or UIColorName in it, or a
        // storyboard, would be a splash screen (phase 8 of the UI design).
        let launchScreen = try #require(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any])
        #expect(launchScreen["UIImageName"] == nil)
        #expect(launchScreen["UIColorName"] == nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "UILaunchStoryboardName") == nil)
    }
#endif

#if canImport(UIKit)
    @Test("The app carries its icon, which an upload rejects the app for lacking")
    func appIconShips() throws {
        // actool merges the icon sets into Info.plist and writes the primary
        // icon's files into the bundle; an empty set produces neither.
        let icons = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
        #expect(Bundle.main.url(forResource: "AppIcon60x60@2x", withExtension: "png") != nil)
    }
#endif

    /// Apple's required-reason APIs as they are spelt in Swift, by manifest
    /// category (developer.apple.com, "Describing use of required reason API").
    static let requiredReasonPatterns: [String: [String]] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": [#"\bUserDefaults\b"#, #"@AppStorage\b"#],
        "NSPrivacyAccessedAPICategorySystemBootTime": [#"\bsystemUptime\b"#, #"\bmach_absolute_time\b"#],
        "NSPrivacyAccessedAPICategoryFileTimestamp": [
            #"\b(creationDateKey|contentModificationDateKey|attributeModificationDateKey|fileModificationDate)\b"#,
            #"FileAttributeKey\.(creationDate|modificationDate)\b"#,
            #"\b(f|l)?stat(at)?\("#, #"\bf?getattrlist(bulk|at)?\("#,
        ],
        "NSPrivacyAccessedAPICategoryDiskSpace": [
            #"\bvolume(Available|Total)Capacity\w*Key\b"#, #"\bsystem(Free)?Size\b"#, #"\bf?statv?fs\("#,
        ],
        "NSPrivacyAccessedAPICategoryActiveKeyboards": [#"\bactiveInputModes\b"#],
    ]

    /// Which required-reason categories the Swift files under `folders`
    /// (relative to the repo root) use, each with the files and lines that use
    /// it. Comments are skipped. A folder that isn't there is skipped too, so
    /// the open-source tree and the App Store's can share the call; finding no
    /// Swift file at all records an issue.
    static func requiredReasonCategories(in folders: [String], excluding excluded: [String] = []) throws -> [String: [String]] {
        let root = TestPaths.repoRoot
        // Simple word boundaries: Unicode's take `processInfo.systemUptime`
        // as one word, so `\bsystemUptime` would never match it.
        let patterns = try requiredReasonPatterns.mapValues { try $0.map { try Regex($0).wordBoundaryKind(.simple) } }
        var used: [String: [String]] = [:]
        var files = 0
        for folder in folders {
            guard let walk = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk where url.pathExtension == "swift" {
                let relative = String(url.path.dropFirst(root.path.count + 1))
                if excluded.contains(where: { relative.hasPrefix($0 + "/") }) { continue }
                files += 1
                let text = try String(contentsOf: url, encoding: .utf8)
                for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    let code = line.firstRange(of: "//").map { line[..<$0.lowerBound] } ?? line
                    for (category, regexes) in patterns where regexes.contains(where: { code.contains($0) }) {
                        used[category, default: []].append("\(relative):\(number + 1)")
                    }
                }
            }
        }
        if files == 0 { Issue.record("No Swift files under \(folders) in \(root.path)") }
        return used
    }

    /// The manifest as the app carries it. Tests run inside the app, so
    /// `Bundle.main` is the app's bundle, not the test bundle's. Internal:
    /// the App Store edition's checks read it too (Pro/AppStoreReadinessTests+Pro.swift).
    static func privacyManifest() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
