//
//  AdConfig.swift
//  NoteCode
//
//  Which AdMob ids each build uses, and the rules for when a banner shows.
//

import Foundation

/// The AdMob ids. **Release builds use ours, every other build Google's
/// published test ids**, so a developer tapping a banner can never be counted
/// as a click on a real unit. `forRelease` is a parameter so a test can pin
/// both sets whatever configuration it runs under.
struct AdConfig: Equatable, Sendable {
    let homeBannerUnit: String
    let listBannerUnit: String

    /// The app id also sits in Info.plist (`GADApplicationIdentifier`), which
    /// the SDK reads itself; it is kept here so a test can check the two agree.
    static let appID = "ca-app-pub-4284419042550157~8825821662"

    static let real = AdConfig(
        homeBannerUnit: "ca-app-pub-4284419042550157/3375938454",
        listBannerUnit: "ca-app-pub-4284419042550157/7512739996"
    )

    /// Google's sample banner unit, which always fills with a test ad.
    static let test = AdConfig(
        homeBannerUnit: "ca-app-pub-3940256099942544/2435281174",
        listBannerUnit: "ca-app-pub-3940256099942544/2435281174"
    )

    static func units(forRelease: Bool) -> AdConfig { forRelease ? .real : .test }

    static var current: AdConfig {
#if DEBUG
        units(forRelease: false)
#else
        units(forRelease: true)
#endif
    }
}

/// Where a banner can sit.
enum AdPlacement: Sendable {
    case home, list

    func unitID(_ config: AdConfig = .current) -> String {
        switch self {
        case .home: config.homeBannerUnit
        case .list: config.listBannerUnit
        }
    }
}

/// When a banner is on screen. Free readers only, and only once consent has
/// been gathered; Pro removes it at once because both inputs are observed.
func adBannerShows(isPro: Bool, canRequestAds: Bool) -> Bool {
    !isPro && canRequestAds
}
