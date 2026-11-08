//
//  RunTopBarItem.swift
//  NoteCode
//
//  Run's item in the note's top bar. Split from RunPanel.swift (D4).
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// Run's item in the note's top bar (`RunFeature.topBarItem`).
struct RunTopBarItem: View {
    var session: RunSession
    var layout: EditorPageLayout
    var isPro: @MainActor () -> Bool
    var onSelect: (Bool) -> Void

    var body: some View {
        if layout.isCompact || (layout.windowWidth > 0 && layout.windowWidth < HomeLayout.regularMinimumWidth) {
            // A phone's bar has no room for the switch beside the
            // title, and the overflow menu it goes to drops a picker
            // (iPhone 17, 31 Oct): a button lands there as a row. A
            // narrow regular window too, where the switch cut the
            // title to "Week 6 · Has…" (an upright Duo, 669pt).
            Button(session.isOpen ? "Back to Notes" : "Run", systemImage: session.isOpen ? "doc.text" : "play") {
                onSelect(!session.isOpen)
            }
        } else {
            NotesRunToggle(
                isRun: session.isOpen,
                showsProMark: !isPro(),
                onSelect: onSelect
            )
        }
    }
}

#endif
