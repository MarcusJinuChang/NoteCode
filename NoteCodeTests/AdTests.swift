//
//  AdTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Ads", .serialized)
@MainActor
struct AdTests {

    /// Records what the ad stack was asked, in order.
    final class FakePlatform: AdPlatform {
        var calls: [String] = []
        var consentGranted = true
        func gatherConsent() async -> Bool { calls.append("consent"); return consentGranted }
        func startSDK() async { calls.append("start") }
        func trackingAllowed() -> Bool? { nil }
        func requestTracking() async { calls.append("tracking") }
    }

    private func defaults() -> UserDefaults {
        let name = "AdTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("Each configuration uses its own ids: real in Release, Google's test ids otherwise")
    func ids() {
        let real = AdConfig.units(forRelease: true)
        #expect(real.homeBannerUnit == "ca-app-pub-4284419042550157/3375938454")
        #expect(real.listBannerUnit == "ca-app-pub-4284419042550157/7512739996")
        let test = AdConfig.units(forRelease: false)
        #expect(test.homeBannerUnit.hasPrefix("ca-app-pub-3940256099942544/"))
        #expect(test.listBannerUnit.hasPrefix("ca-app-pub-3940256099942544/"))
#if DEBUG
        #expect(AdConfig.current == test)
#else
        #expect(AdConfig.current == real)
#endif
        #expect(AdPlacement.home.unitID(real) == real.homeBannerUnit)
        #expect(AdPlacement.list.unitID(real) == real.listBannerUnit)
    }

    @Test("Info.plist carries the app id, the tracking reason and the SKAdNetwork list")
    func plist() throws {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["GADApplicationIdentifier"] as? String == AdConfig.appID)
        #expect((info["NSUserTrackingUsageDescription"] as? String)?.contains("never shared") == true)
        let items = info["SKAdNetworkItems"] as? [[String: String]] ?? []
        #expect(items.contains { $0["SKAdNetworkIdentifier"] == "cstr6suwn9.skadnetwork" })
    }

    @Test("Free shows a banner once ads may be requested; Pro never does")
    func shows() {
        #expect(adBannerShows(isPro: false, canRequestAds: true))
        #expect(!adBannerShows(isPro: true, canRequestAds: true))
        #expect(!adBannerShows(isPro: false, canRequestAds: false), "no banner before consent")
    }

    @Test("Nothing is asked at creation; the first Home visit gathers consent and starts the SDK, not tracking")
    func firstVisit() async {
        let platform = FakePlatform()
        let consent = AdConsent(platform: platform, defaults: defaults())
        #expect(platform.calls.isEmpty, "not at launch")
        await consent.homeAppeared(isPro: false)
        #expect(platform.calls == ["consent", "start"])
        #expect(consent.canRequestAds)
    }

    @Test("The tracking prompt waits for a later Home visit")
    func laterVisit() async {
        let platform = FakePlatform()
        let consent = AdConsent(platform: platform, defaults: defaults())
        await consent.homeAppeared(isPro: false)
        await consent.homeAppeared(isPro: false)
        #expect(platform.calls == ["consent", "start", "tracking"])
    }

    @Test("A refused consent form starts nothing and shows no banner")
    func refused() async {
        let platform = FakePlatform()
        platform.consentGranted = false
        let consent = AdConsent(platform: platform, defaults: defaults())
        await consent.homeAppeared(isPro: false)
        #expect(platform.calls == ["consent"])
        #expect(!consent.canRequestAds)
    }

    @Test("A Pro reader's Home visit touches the ad stack not at all")
    func pro() async {
        let platform = FakePlatform()
        let consent = AdConsent(platform: platform, defaults: defaults())
        await consent.homeAppeared(isPro: true)
        #expect(platform.calls.isEmpty)
    }
}
