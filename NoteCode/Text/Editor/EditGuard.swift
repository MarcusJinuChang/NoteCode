//
//  EditGuard.swift
//  NoteCode
//
//  The re-entrancy flags of the text system, in one place. Each says "the
//  app is making this edit itself", so the delegate callbacks the edit
//  causes don't take it for the keyboard's. They used to be five Bools on
//  two classes (`isFormatting` and `isWritingTypedText` on NoteEditor,
//  `isApplyingMarkerEdit`, `isRetagging` and `isNormalizingCaret` on the
//  Coordinator and CodeFenceDisplay), each set and cleared by hand around
//  the edit. `perform(as:_:)` sets one for the length of a closure and
//  clears it however the closure ends, so a flag can't be left set.
//

import Foundation

@MainActor
final class EditGuard {

    enum Kind: Int, CaseIterable {
        /// A formatting button's edit, or one made for the Select tool,
        /// going through the text view (`NoteEditor`).
        case formatting
        /// An edit of the coordinator's own (a Backspace at a hidden marker,
        /// a list's Return), so `shouldChangeTextIn` doesn't take it for
        /// another keystroke.
        case markerEdit
        /// A language pick rewriting a fence's tag, which the
        /// keyboard-rewrite guard would turn away: it replaces text that
        /// isn't the selection, in code.
        case retagging
        /// The caret being moved off the inside of a hidden marker, which
        /// is a selection change of its own.
        case normalizingCaret
        /// The typing style's text being written (`NoteEditor`), whose
        /// selection change is not the reader moving the caret.
        case writingTypedText
    }

    /// How many `perform` calls of each kind are open, so one nested in
    /// another of the same kind doesn't clear the flag early.
    private var depth = [Int](repeating: 0, count: Kind.allCases.count)

    func isActive(_ kind: Kind) -> Bool {
        depth[kind.rawValue] > 0
    }

    /// Runs `body` with the flag set, and clears it however `body` ends.
    @discardableResult
    func perform<Result>(as kind: Kind, _ body: () throws -> Result) rethrows -> Result {
        depth[kind.rawValue] += 1
        defer { depth[kind.rawValue] -= 1 }
        return try body()
    }

    /// A formatting button's edit is going through the text view.
    var isFormatting: Bool { isActive(.formatting) }

    /// The app is replacing text itself, by a formatting edit or a marker
    /// edit: UIKit's smart punctuation must leave its text alone.
    var isReplacingForTheReader: Bool { isActive(.formatting) || isActive(.markerEdit) }

    /// The text in flight came from the app rather than the keyboard
    /// (formatting, a marker edit or a retag).
    var isAppEdit: Bool { isActive(.formatting) || isActive(.markerEdit) || isActive(.retagging) }
}
