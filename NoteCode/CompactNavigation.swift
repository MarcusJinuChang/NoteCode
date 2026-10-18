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
