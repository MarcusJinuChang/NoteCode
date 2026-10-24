//
//  CompactNavigation.swift
//  NoteCode
//
//  The stack a compact width shows in place of the split view: an iPhone, a
//  folded Duo, a narrow Split View (roadmap step 11).
//

import SwiftUI

/// What a compact width's stack can have pushed on Home, and the rules that
/// keep it in step with the open note and with the split view.
nonisolated enum CompactScreen: Hashable, Sendable {
    case list
    case note

    /// The stack once a note opens or closes: an opened note is pushed on
    /// whatever is showing, Home or the list; a closed one is popped, leaving
    /// what it was opened from.
    static func path(_ path: [CompactScreen], noteOpen: Bool) -> [CompactScreen] {
        if noteOpen {
            return path.last == .note ? path : path + [.note]
        }
        return path.filter { $0 != .note }
    }

    /// The stack that shows what a split view showed: the list if it was over
    /// the page or Home, and the note on top if one was open.
    static func path(listShowing: Bool, noteOpen: Bool) -> [CompactScreen] {
        (listShowing ? [.list] : []) + (noteOpen ? [.note] : [])
    }

    /// Whether the list is what the stack shows, so a split view brings it
    /// over the page.
    static func listShowing(in path: [CompactScreen]) -> Bool {
        path.last == .list
    }
}

/// Whether the split view shows the list (regular width), by what is open.
///
/// Home is the one place the list is always beside you: it has nothing to be
/// covered. Over a note the list slides over the page and goes away when a
/// note opens (see "The page fills the window" in AGENTS.md: opening it never
/// re-wraps or rescales the note).
nonisolated enum SidebarPlan {
    /// How long after launch the list is brought in beside Home. A split view
    /// that *starts* with its sidebar visible pinned the main thread at 100%
    /// CPU in the iPad simulator (a layout-descriptor walk in AttributeGraph,
    /// sampled 24 Oct, iOS 27.0 debug build): the unmodified build was fine
    /// with the list shown later, over Home by ☰, and so is this. Showing it
    /// after the first layout avoids it; the cause is not understood.
    static let launchDelay = Duration.milliseconds(400)

    /// Whether the list is showing when `noteOpen` changes or the window is
    /// made: with Home up, yes; with a note open, only with storage failed,
    /// whose warning is the list's.
    static func showsList(noteOpen: Bool, storageFailed: Bool) -> Bool {
        !noteOpen || storageFailed
    }

    /// Whether the split view shows the list once it takes over from a stack:
    /// always on Home, and over a note only if the list was what the stack
    /// showed.
    static func showsList(unfoldingFrom path: [CompactScreen], noteOpen: Bool) -> Bool {
        !noteOpen || CompactScreen.listShowing(in: path)
    }

    /// What the stack starts with when a split view folds into it: the list
    /// only if it was over a note, since on Home the list is beside it and a
    /// stack's Home is the root, not a list pushed on it.
    static func stackShowsList(listShowing: Bool, noteOpen: Bool) -> Bool {
        listShowing && noteOpen
    }
}

/// A list row that opens its note on a tap in a compact width.
///
/// The list's rows open by selection (`List(selection:)` and `.tag`), which
/// the iPad's sidebar turns a tap into. In a stack on an iPhone a tap
/// selects nothing outside edit mode, and the binding is never set (logged,
/// 17 Oct), so there the row takes the tap itself. Nothing changes in a
/// regular width, where the selection does it.
struct OpensOnTapInCompactWidth: ViewModifier {
    var open: () -> Void

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
#endif

    func body(content: Content) -> some View {
#if os(iOS)
        if sizeClass == .compact {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture(perform: open)
        } else {
            content
        }
#else
        content
#endif
    }
}

extension View {
    func opensOnTapInCompactWidth(_ open: @escaping () -> Void) -> some View {
        modifier(OpensOnTapInCompactWidth(open: open))
    }
}
