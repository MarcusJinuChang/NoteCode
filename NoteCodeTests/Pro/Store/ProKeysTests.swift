//
//  ProKeysTests.swift
//  NoteCodeTests
//
//  The names and ids Pro depends on. A renamed settings key orphans what a
//  device saved; a changed product id stops the store finding the product,
//  and the run proxy (`server/run-proxy/wrangler.toml`: `PRO_PRODUCT_IDS`,
//  `BUNDLE_ID`) checks the same ones, so a change here must change there.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Pro keys and ids", .tags(.pro))
@MainActor
struct ProKeysTests {

    @Test("The Pro-side settings keep the names devices saved them under")
    func settingsKeys() {
        #expect(AIFeatureSettings.enabledKey == "aiEnabled")
        #expect(AIFeatureSettings.lengthKey == "aiAnswerLength")
        #expect(AIFeatureSettings.insertStyleKey == "aiInsertStyle")
        #expect(RunDockWidth.key == "runPanelWidth")
        #expect(RunDisclosure.key == "runDisclosureAccepted")
    }

    @Test("The Pro-side settings start on their defaults")
    func settingsDefaults() {
        #expect(AIFeatureSettings().isEnabled == true)
        #expect(AIAnswerLength.standard.rawValue == "standard")
        #expect(AIInsertStyle.quote.rawValue == "quote")
        #expect(RunDockWidth.initial == 360.0)
    }

    @Test("The ad visit count is kept under adHomeVisits")
    func adHomeVisits() throws {
        let suite = "ProKeysTests.ads.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = AdConsent(platform: NoPlatform(), defaults: defaults)
        #expect(consent.homeVisits == 0)
        defaults.set(7, forKey: "adHomeVisits")
        #expect(consent.homeVisits == 7)
    }

    @Test("The bundle id and the product ids are the ones the store and the run proxy know")
    func ids() {
        #expect(Bundle.main.bundleIdentifier == "com.marcus.NoteCode")
        #expect(ProStatus.productID == "com.marcus.NoteCode.pro.monthly")
        #expect(TipJar.productIDs == [
            "com.marcus.NoteCode.tip.small",
            "com.marcus.NoteCode.tip.medium",
            "com.marcus.NoteCode.tip.large",
        ])
    }

    private final class NoPlatform: AdPlatform {
        func gatherConsent() async -> Bool { false }
        func startSDK() async {}
        func trackingAllowed() -> Bool? { nil }
        func requestTracking() async {}
        func updateConsentInfo() async {}
        func privacyOptionsRequired() -> Bool { false }
        func presentPrivacyOptions() async {}
    }
}
