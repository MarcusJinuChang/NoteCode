//
//  PageDetailView+Run.swift
//  NoteCode
//

import SwiftUI

#if canImport(UIKit)
extension PageDetailView {
    /// The Notes | Run control, on the right with Share and •••. Not
    /// `.principal`, which replaces the title: the note's name and its menu
    /// went, leaving a bare chevron.
    @ToolbarContentBuilder
    var runToggleItem: some ToolbarContent {
        if let run = editor.run, run.isAvailable {
            ToolbarItem(placement: .primaryAction) {
                if isCompact || (windowWidth > 0 && windowWidth < HomeLayout.regularMinimumWidth) {
                    // A phone's bar has no room for the switch beside the
                    // title, and the overflow menu it goes to drops a picker
                    // (iPhone 17, 31 Oct): a button lands there as a row. A
                    // narrow regular window too, where the switch cut the
                    // title to "Week 6 · Has…" (an upright Duo, 669pt).
                    Button(run.isOpen ? "Back to Notes" : "Run", systemImage: run.isOpen ? "doc.text" : "play") {
                        showRun(!run.isOpen)
                    }
                } else {
                    NotesRunToggle(
                        isRun: run.isOpen,
                        showsProMark: !ProGate.isPro,
                        onSelect: showRun
                    )
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    func showRun(_ wantsRun: Bool) {
        if !wantsRun {
            withAnimation(.snappy) { editor.run?.isOpen = false }
        } else if ProGate.isPro {
            withAnimation(.snappy) { editor.run?.isOpen = true; editor.run?.isCollapsed = false }
        } else {
            showsRunPaywall = true
        }
    }

    /// The note, with the Run panel docked at its right where there is room.
    /// The panel narrows the page's area and nothing else: the page's zoom
    /// and place are its own.
    var runLayout: some View {
        HStack(spacing: 0) {
            content
            if let run = editor.run, run.isOpen, !isCompact {
                RunDock(
                    session: run,
                    transaction: { ProGate.signedTransaction },
                    onShow: { editor.scroll(toLineAt: $0.location) },
                    availableWidth: windowWidth
                )
                .transition(.move(edge: .trailing))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
    }
}
#endif
