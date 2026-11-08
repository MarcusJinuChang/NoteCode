//
//  RunPanelHost.swift
//  NoteCode
//
//  What a note's page keeps behind it for Run. Split from RunPanel.swift (D4).
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// What a note's page keeps behind it for Run (`RunFeature.pageAccessory`):
/// the paywall's opening, the bottom sheet in a compact width, the free
/// reader's paywall, and the debug stub's autorun. The runner is the
/// feature's.
struct RunPanelHost: View {
    let feature: RunFeature
    /// The signed transaction each run sends (`ProGate.signedTransaction`).
    var transaction: () -> String

    /// Run was chosen by a free reader: the paywall opens, with Run's reason,
    /// instead of the panel.
    @State private var showsRunPaywall = false

#if os(iOS)
    @Environment(\.layoutClass) private var layoutClass
    private var isCompact: Bool { layoutClass.isCompact }
#else
    private var isCompact: Bool { false }
#endif

    private var session: RunSession { feature.session }

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .task {
                // The binding alone: the feature is the editor's, so a hook
                // that held this host would hold the editor (F1).
                feature.onNeedsPro = { [paywall = $showsRunPaywall] in paywall.wrappedValue = true }
#if DEBUG
                if ProDebugOptions.current.runStub != nil {
                    try? await Task.sleep(for: .seconds(1))
                    session.isOpen = true
                    session.run(transaction: transaction())
                }
#endif
            }
            .sheet(isPresented: Binding(
                get: { session.isOpen && isCompact },
                set: { if !$0 { session.isOpen = false } }
            )) {
                RunPanel(session: session, transaction: transaction, onShow: Self.scroller(for: feature))
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .paywall(isPresented: $showsRunPaywall, reason: ProGate.Reason.runInApp)
    }

    /// Scrolls the note to a block. Holds the feature weakly, so the panel
    /// never keeps the editor alive (F1). Made outside the sheet's closure,
    /// which captures this host and with it the feature, strongly.
    private static func scroller(for feature: RunFeature) -> (RunBlock) -> Void {
        { [weak feature] in feature?.editor?.scroll(toLineAt: $0.location) }
    }
}

#endif
