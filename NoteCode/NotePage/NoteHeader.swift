//
//  NoteHeader.swift
//  NoteCode
//
//  The note's navigation bar items. They were `headerItems` in
//  `PageDetailView`; the ••• menu is `NoteMoreMenu`.
//

import SwiftUI

/// Home beside the sidebar button; Share and ••• on the right, in the label
/// colour, not the accent, which belongs to the tools and the page. The
/// sidebar button on the left is the system's: it opens the list over the
/// page, and in a compact width the back button takes its place.
struct NoteHeader: ToolbarContent {
    let page: Page
    let onToggleList: (() -> Void)?
    let onGoHome: (() -> Void)?
    let more: NoteMoreMenu
#if canImport(UIKit)
    let editor: NoteEditor
    /// What the features are told about the page's room.
    let layout: EditorPageLayout
#endif

    var body: some ToolbarContent {
        // The title is the system's, so it can't carry the lock after it;
        // the lock sits beside the buttons instead, only while it's locked.
        if page.isTextLocked {
            ToolbarItem(placement: .primaryAction) {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Text Locked")
            }
        }

        // Beside the sidebar button, at the top left. The house goes where
        // the list's Home row was: the list is no longer where Home lives.
        if let onToggleList {
            ToolbarItem(placement: homePlacement) {
                NoteWindowControl(onToggleList: onToggleList, onGoHome: onGoHome)
            }
            .sharedBackgroundVisibility(.hidden)
        }

#if canImport(UIKit)
        // A feature's item, on the right with Share and •••: the first
        // feature that offers one. Not `.principal`, which replaces the
        // title: the note's name and its menu went, leaving a bare chevron.
        if let item = editor.features.lazy.compactMap({ $0.topBarItem(in: layout) }).first {
            ToolbarItem(placement: .primaryAction) {
                item
            }
            .sharedBackgroundVisibility(.hidden)
        }

        ToolbarItem(placement: .primaryAction) {
            NoteShareButton(editor: editor, title: page.displayTitle, fallbackText: page.content)
                .tint(.primary)
        }
        .sharedBackgroundVisibility(.hidden)
#endif

        ToolbarItem(placement: .primaryAction) {
            more
                .tint(.primary)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    /// The top left. `.topBarLeading` is iOS's only; the Mac's leading
    /// place in a window's toolbar is `.navigation`.
    private var homePlacement: ToolbarItemPlacement {
#if os(iOS)
        .topBarLeading
#else
        .navigation
#endif
    }
}
