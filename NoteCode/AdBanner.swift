//
//  AdBanner.swift
//  NoteCode
//
//  The banner for readers without Pro, at Home's foot and in the list's foot.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
import GoogleMobileAds
#endif

/// A banner and "Remove ads" under it, or nothing: Pro, no consent yet, or
/// (in tests) no ad stack. Placed only in Home and the list's foot, so no
/// note, Settings, paywall or sheet has one.
struct AdSlot: View {
    let placement: AdPlacement
    /// Absent (previews, tests) reads as Pro: no ad stack without a status.
    @Environment(ProStatus.self) private var pro: ProStatus?
    @State private var consent = AdConsent.shared
    @State private var showsPaywall = false

    var body: some View {
        if adBannerShows(isPro: pro?.isPro ?? true, canRequestAds: consent.canRequestAds) {
            VStack(spacing: 4) {
                AdBanner(unitID: placement.unitID(), personalised: consent.personalised)
                Button("Remove ads") { showsPaywall = true }
                    .font(.footnote)
                    .accessibilityIdentifier("removeAdsButton")
            }
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $showsPaywall) {
                PaywallView(reason: "Pro removes the ads.")
            }
        }
    }
}

#if canImport(UIKit)
/// `BannerView` at the adaptive anchored size for the width it is given.
struct AdBanner: View {
    let unitID: String
    let personalised: Bool
    @State private var width: CGFloat = 0

    var body: some View {
        let size = width > 0 ? largeAnchoredAdaptiveBanner(width: width) : AdSizeBanner
        BannerRepresentable(unitID: unitID, personalised: personalised, size: size)
            .frame(height: size.size.height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .frame(maxWidth: .infinity)
    }
}

private struct BannerRepresentable: UIViewRepresentable {
    let unitID: String
    let personalised: Bool
    let size: AdSize

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: size)
        banner.adUnitID = unitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        context.coordinator.loadedWidth = size.size.width
        banner.load(request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        guard context.coordinator.loadedWidth != size.size.width else { return }
        context.coordinator.loadedWidth = size.size.width
        banner.adSize = size
        banner.load(request())
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loadedWidth: CGFloat = 0 }

    private func request() -> Request {
        let request = Request()
        if !personalised {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }
        return request
    }
}
#else
struct AdBanner: View {
    let unitID: String
    let personalised: Bool
    var body: some View { EmptyView() }
}
#endif
