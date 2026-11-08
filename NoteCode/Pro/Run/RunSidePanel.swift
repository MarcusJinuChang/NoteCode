//
//  RunSidePanel.swift
//  NoteCode
//
//  The dock beside the page in a regular width. Split from RunPanel.swift (D4).
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// The dock beside the page while the panel is open, in a regular width
/// (`RunFeature.sidePanel`); a compact width has the sheet instead.
struct RunSidePanel: View {
    var session: RunSession
    var layout: EditorPageLayout
    var transaction: () -> String
    var onShow: (RunBlock) -> Void

    var body: some View {
        if session.isOpen, !layout.isCompact {
            RunDock(
                session: session,
                transaction: transaction,
                onShow: onShow,
                availableWidth: layout.windowWidth
            )
            .transition(.move(edge: .trailing))
        }
    }
}

#endif
