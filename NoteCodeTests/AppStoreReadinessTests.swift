//
//  AppStoreReadinessTests.swift
//  NoteCodeTests
//
//  What an upload to App Store Connect checks before a person ever sees the
//  app. Each of these would bounce an upload or raise a question in review,
//  and none of them shows up in the app itself.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Ready for the App Store")
struct AppStoreReadinessTests {

    @Test("The privacy manifest ships in the app and declares what the ad SDK tracks")
    func privacyManifest() throws {
        let manifest = try Self.privacyManifest()

        // Ads (P3): tracking is on, with the domains Google's SDK contacts,
        // and every collected type is for third-party advertising, unlinked
        // from the reader. Notes are never among them.
        #expect(manifest["NSPrivacyTracking"] as? Bool == true)
        let domains = try #require(manifest["NSPrivacyTrackingDomains"] as? [String])
        #expect(domains.contains("doubleclick.net") && domains.contains("googlesyndication.com"))
        let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        #expect(!collected.isEmpty)
        for item in collected {
            #expect(item["NSPrivacyCollectedDataTypeLinked"] as? Bool == false)
            #expect(item["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising"])
        }
    }

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

    @Test("The app says it uses only exempt encryption, so uploads skip the question")
    func exemptEncryption() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool == false)
    }

    @Test("The privacy policy link is https, and the drafted page covers Run and ads")
    func privacyPolicyPage() throws {
        #expect(AppInfo.privacyPolicy.scheme == "https")

        // docs/site/privacy.md is the text published on gh-pages. Read it from
        // the source tree; on a machine without the tree there is nothing to check.
        let page = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/site/privacy.md")
        guard let text = try? String(contentsOf: page, encoding: .utf8) else { return }
        for phrase in ["Judge0", "Running code in the app", "Ads", "tracking", "Pro"] {
            #expect(text.contains(phrase), "privacy.md should mention \(phrase)")
        }
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

    /// The manifest as the app carries it. Tests run inside the app, so
    /// `Bundle.main` is the app's bundle, not the test bundle's.
    private static func privacyManifest() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
