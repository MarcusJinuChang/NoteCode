//
//  AdTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
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
        /// What UMP says about Privacy Options. A read, so not in `calls`.
        var optionsRequired = false
        func updateConsentInfo() async { calls.append("update") }
        func privacyOptionsRequired() -> Bool { optionsRequired }
        func presentPrivacyOptions() async { calls.append("options") }
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

    @Test("Consent waits for the launch to decide about the title screen, and for it to go")
    func gate() {
        #expect(!ConsentGate.isOpen(launchSettled: false, titleScreenUp: false), "Home's first appearance, before the screen is decided")
        #expect(!ConsentGate.isOpen(launchSettled: true, titleScreenUp: true), "over the title screen")
        #expect(ConsentGate.isOpen(launchSettled: true, titleScreenUp: false), "Home is in front")
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

    // QC A4: a way to change the consent answer (guideline 5.1.1(ii)).

    @Test("Where UMP requires it, Home's consent turns on Ad Privacy Options, and the row opens Google's form")
    func privacyOptionsAfterHome() async {
        let platform = FakePlatform()
        platform.optionsRequired = true
        let consent = AdConsent(platform: platform, defaults: defaults())
        #expect(!consent.privacyOptionsRequired)
        await consent.homeAppeared(isPro: false)
        #expect(consent.privacyOptionsRequired)

        await consent.settingsAppeared(isPro: false)
        #expect(platform.calls == ["consent", "start"], "UMP was already asked this launch")

        await consent.showPrivacyOptions()
        #expect(platform.calls.last == "options")
    }

    @Test("Declining the consent form still offers Ad Privacy Options, to change the answer")
    func privacyOptionsAfterDecline() async {
        let platform = FakePlatform()
        platform.consentGranted = false
        platform.optionsRequired = true
        let consent = AdConsent(platform: platform, defaults: defaults())
        await consent.homeAppeared(isPro: false)
        #expect(consent.privacyOptionsRequired)
    }

    @Test("A launch straight into a note: Help and About asks UMP once, showing nothing, then knows")
    func privacyOptionsWithoutHome() async {
        let platform = FakePlatform()
        platform.optionsRequired = true
        let consent = AdConsent(platform: platform, defaults: defaults())
        await consent.settingsAppeared(isPro: false)
        await consent.settingsAppeared(isPro: false)
        #expect(platform.calls == ["update"])
        #expect(consent.privacyOptionsRequired)
    }

    @Test("Where UMP doesn't require it, or for Pro, there is no row")
    func noPrivacyOptions() async {
        let outside = FakePlatform()
        let consent = AdConsent(platform: outside, defaults: defaults())
        await consent.homeAppeared(isPro: false)
        await consent.settingsAppeared(isPro: false)
        #expect(!consent.privacyOptionsRequired)

        let platform = FakePlatform()
        platform.optionsRequired = true
        let pro = AdConsent(platform: platform, defaults: defaults())
        await pro.settingsAppeared(isPro: true)
        #expect(platform.calls.isEmpty, "Pro never hears from the ad stack")
        #expect(!pro.privacyOptionsRequired)
    }

#if canImport(UIKit)
    @Test("The banner takes the width it is given, never its ad's")
    func bannerFitsItsPlace() async throws {
        // Narrower than the 320pt banner the ad stack starts from. Sized from
        // its own width, the banner held Home at 1720pt in an 1180pt window.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        let host = UIHostingController(rootView: AdBanner(unitID: AdPlacement.home.unitID(), personalised: false))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(50))
            host.view.layoutIfNeeded()
        }

        let banner = try #require(Self.bannerView(in: host.view))
        #expect(banner.convert(banner.bounds, to: window).width <= 300)
        #expect(host.sizeThatFits(in: CGSize(width: 300, height: 400)).width <= 300)
    }

    /// The SDK's banner, found by class name: the tests don't link the SDK.
    private static func bannerView(in view: UIView) -> UIView? {
        if NSStringFromClass(type(of: view)) == "GADBannerView" { return view }
        return view.subviews.lazy.compactMap { bannerView(in: $0) }.first
    }
#endif
}
