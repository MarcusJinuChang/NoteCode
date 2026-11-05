//
//  OpenSourceEditionTests.swift
//  NoteCodeTests
//
//  What the open-source edition ships instead of the App Store's ads:
//  a privacy manifest with no tracking, and an Info.plist with no ad SDK
//  keys. Outside NoteCodeTests/, so the App Store build doesn't compile it;
//  scripts/build-open-source.sh copies it into NoteCodeTests/App/.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Ready for the App Store: the open-source edition", .tags(.library))
struct OpenSourceEditionTests {

    @Test("The privacy manifest declares no tracking, no tracking domains and no collected data")
    func noTracking() throws {
        let manifest = try AppStoreReadinessTests.privacyManifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty ?? true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty ?? true)
    }

    @Test("Info.plist carries none of the ad SDK's keys")
    func noAdKeys() {
        for key in ["GADApplicationIdentifier", "SKAdNetworkItems", "NSUserTrackingUsageDescription"] {
            #expect(Bundle.main.object(forInfoDictionaryKey: key) == nil, "\(key) should not be in the public Info.plist")
        }
    }
}
