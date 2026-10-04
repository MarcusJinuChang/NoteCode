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

    @Test("The privacy manifest ships in the app, tracking and collecting nothing")
    func privacyManifest() throws {
        let manifest = try Self.privacyManifest()

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
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

    @Test("The app declares no background modes, since it uses none")
    func noBackgroundModes() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") == nil)
    }

    /// The manifest as the app carries it. Tests run inside the app, so
    /// `Bundle.main` is the app's bundle, not the test bundle's.
    private static func privacyManifest() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
