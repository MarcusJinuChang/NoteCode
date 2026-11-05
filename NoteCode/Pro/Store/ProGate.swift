//
//  ProGate.swift
//  NoteCode
//
//  The one way to ask whether the reader has Pro, and to show the paywall.
//

import SwiftUI

/// Whether the reader has Pro, the signed transaction that proves it, and why
/// the paywall opened. **The only "is Pro" check outside `Pro/Store/`**: the
/// note window's Run control, the editor's Run gate, the assistant and the ad
/// slot all read `isPro` here (docs/refactor/2X-seam.md › 2X2).
///
/// It reads `ProStatus.shared`, which the App Store edition starts at launch
/// and puts in the environment, so it is the same status the views' own
/// `@Environment(ProStatus.self)` hold, and a view that reads it in `body` is
/// redrawn when it changes (renewal, refund, a purchase).
@MainActor
enum ProGate {
    /// Whether Pro is on now.
    static var isPro: Bool { ProStatus.shared.isPro }

    /// The signed transaction Run sends to the proxy; empty for a free reader.
    static var signedTransaction: String { ProStatus.shared.signedTransaction ?? "" }

    /// Reads the entitlement again: the proxy said the subscription ended
    /// (a 402) without the app noticing.
    static func refresh() async { await ProStatus.shared.refresh() }

    /// Why the paywall opened, the line above its features. In one place so
    /// each sheet that opens it says the same thing.
    enum Reason {
        static let removesAds = "Pro removes the ads."
        static let runInApp = "Run in the app is part of NoteCode Pro."
        static let assistant = "Explain Code and Summarise Note are part of NoteCode Pro."
    }
}

extension View {
    /// The paywall as a sheet of this view, for a reason (`ProGate.Reason`),
    /// or none from Settings › Pro. Each presenter keeps its own sheet: one
    /// presented from the root while another sheet is up never appears.
    func paywall(isPresented: Binding<Bool>, reason: String? = nil) -> some View {
        sheet(isPresented: isPresented) { PaywallView(reason: reason) }
    }
}
