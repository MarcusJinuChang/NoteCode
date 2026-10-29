//
//  AdConsent.swift
//  NoteCode
//
//  Consent before any ad request: Google's UMP form, then App Tracking
//  Transparency on a later Home visit. The SDK starts only after the first.
//

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform
#endif

/// What `AdConsent` needs from the platform, so a test can watch it and see
/// that nothing is asked at launch.
@MainActor
protocol AdPlatform {
    /// UMP: update the consent state, show the EEA/UK form if one is due.
    /// Returns whether ads may be requested afterwards.
    func gatherConsent() async -> Bool
    /// Starts the Mobile Ads SDK. Called at most once, after consent.
    func startSDK() async
    /// Whether the reader has allowed tracking, nil while not asked.
    func trackingAllowed() -> Bool?
    /// Shows the ATT prompt (a no-op if already answered).
    func requestTracking() async
}

@Observable
@MainActor
final class AdConsent {
    static let shared = AdConsent(platform: SystemAdPlatform(), defaults: .standard)

    private(set) var canRequestAds = false
    /// Non-personalised unless the reader allowed tracking.
    var personalised: Bool { platform.trackingAllowed() == true }

    private let platform: AdPlatform
    private let defaults: UserDefaults
    private var gathering = false
    private static let visitsKey = "adHomeVisits"

    init(platform: AdPlatform, defaults: UserDefaults) {
        self.platform = platform
        self.defaults = defaults
    }

    /// The number of times Home has appeared, across launches.
    var homeVisits: Int { defaults.integer(forKey: Self.visitsKey) }

    /// Home appeared. The first visit gathers consent and starts the SDK; the
    /// tracking prompt waits for a later one, so it is never the first thing
    /// the reader sees and never at launch. Free readers only: Pro never
    /// hears from the ad stack.
    func homeAppeared(isPro: Bool) async {
        guard !isPro, !gathering else { return }
        gathering = true
        defer { gathering = false }
        let visits = homeVisits
        defaults.set(visits + 1, forKey: Self.visitsKey)
        if !canRequestAds {
            guard await platform.gatherConsent() else { return }
            await platform.startSDK()
            canRequestAds = true
        }
        if visits >= 1 { await platform.requestTracking() }
    }
}

#if canImport(UIKit)
@MainActor
struct SystemAdPlatform: AdPlatform {
    func gatherConsent() async -> Bool {
        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { error in
                guard error == nil else {
                    // Offline or the service failed: a previous answer may
                    // still allow ads; otherwise none are requested.
                    continuation.resume(returning: ConsentInformation.shared.canRequestAds)
                    return
                }
                Task { @MainActor in
                    let root = Self.rootViewController()
                    ConsentForm.loadAndPresentIfRequired(from: root) { _ in
                        continuation.resume(returning: ConsentInformation.shared.canRequestAds)
                    }
                }
            }
        }
    }

    func startSDK() async {
        await MobileAds.shared.start()
    }

    func trackingAllowed() -> Bool? {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .authorized: true
        case .notDetermined: nil
        default: false
        }
    }

    func requestTracking() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined,
              UIApplication.shared.applicationState == .active else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
    }
}
#else
@MainActor
struct SystemAdPlatform: AdPlatform {
    func gatherConsent() async -> Bool { false }
    func startSDK() async {}
    func trackingAllowed() -> Bool? { false }
    func requestTracking() async {}
}
#endif
