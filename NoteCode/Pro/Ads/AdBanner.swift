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
///
/// - `opaque`: Home's strip. It has its own surface and a hairline above, so
///   the ad and the link never sit on anything else (the list's slot is a
///   row, which has a surface already).
struct AdSlot: View {
    let placement: AdPlacement
    var opaque = false
    /// Absent (previews, tests) reads as Pro: no ad stack without a status.
    @Environment(ProStatus.self) private var pro: ProStatus?
    @State private var consent = AdConsent.shared
    @State private var showsPaywall = false

    var body: some View {
        if adBannerShows(isPro: pro?.isPro ?? true, canRequestAds: consent.canRequestAds) {
            VStack(spacing: 0) {
                AdBanner(unitID: placement.unitID(), personalised: consent.personalised)
                // Under the ad, in the slot's own strip, so it covers nothing.
                Button("Remove ads") { showsPaywall = true }
                    .font(.footnote)
                    .frame(minHeight: 28)
                    .accessibilityIdentifier("removeAdsButton")
            }
            .frame(maxWidth: .infinity)
            .background {
                if opaque {
                    HomePalette.card
                        .overlay(alignment: .top) { HomePalette.separator.frame(height: 0.5) }
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView(reason: "Pro removes the ads.")
            }
        }
    }
}

#if canImport(UIKit)
/// The banner size, in one place. **The standard anchored adaptive banner**,
/// not the large one (31 Oct): the large size is up to 150pt tall on an iPad,
/// a seventh of an iPad mini's landscape screen on a page whose point is the
/// notes, and Marcus found it too much. The standard one is 90pt at most
/// (the 728 by 90 leaderboard shape iPads fill). docs/design/shipping.md › Ads.
enum AdSizing {
    static func size(forWidth width: CGFloat) -> AdSize {
        currentOrientationAnchoredAdaptiveBanner(width: width)
    }
}

/// `BannerView` at the adaptive anchored size for the width it is given.
///
/// The width is measured on a placeholder that takes what its container
/// offers, and the banner lies over it at the size worked out from that
/// width, so the banner never sets the layout's width. Measured on the
/// banner itself it fed back on itself: a `BannerView` won't be narrower than
/// its ad, each ad was sized from the last one's width, and Home grew to
/// 1720pt in an 1180pt window (`AdTests.bannerFitsItsPlace`).
struct AdBanner: View {
    let unitID: String
    let personalised: Bool
    @State private var width: CGFloat = 0

    var body: some View {
        let size = width > 0 ? AdSizing.size(forWidth: width) : nil
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: size?.size.height ?? 0)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay {
                // Not before the width is known, so no ad is asked for at a
                // size about to be replaced.
                if let size {
                    BannerRepresentable(unitID: unitID, personalised: personalised, size: size)
                        .frame(width: min(size.size.width, width), height: size.size.height)
                }
            }
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

    /// The size it is offered, never the ad's own: see `AdBanner`.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BannerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? size.size.width, height: size.size.height)
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
