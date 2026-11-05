//
//  AppStoreReadinessTests+Pro.swift
//  NoteCodeTests
//
//  What an upload checks that only the App Store edition has: the ad SDK's
//  tracking in the privacy manifest, and a policy page that covers Run and
//  ads. The open-source edition ships OpenSource/PrivacyInfo.xcprivacy, with
//  no tracking, so these live under Pro/ and leave with it.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Ready for the App Store: the App Store edition", .tags(.library, .pro))
struct AppStoreEditionReadinessTests {

    @Test("The privacy manifest ships in the app and declares what the ad SDK tracks")
    func privacyManifest() throws {
        let manifest = try AppStoreReadinessTests.privacyManifest()

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

    @Test("The privacy policy link is https, and the drafted page covers Run and ads")
    func privacyPolicyPage() throws {
        #expect(AppInfo.privacyPolicy.scheme == "https")

        // docs/site/privacy.md is the text published on gh-pages. Read it from
        // the source tree; a tree that can't be found, or a page that isn't
        // there, fails the test rather than skipping the check.
        let page = TestPaths.repoRoot.appendingPathComponent("docs/site/privacy.md")
        let text = try String(contentsOf: page, encoding: .utf8)
        for phrase in ["Judge0", "Running code in the app", "Ads", "tracking", "Pro"] {
            #expect(text.contains(phrase), "privacy.md should mention \(phrase)")
        }
    }
}
