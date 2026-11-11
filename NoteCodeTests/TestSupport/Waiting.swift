//
//  Waiting.swift
//  NoteCodeTests
//
//  How a test waits for something with no hook of its own to await: one
//  bounded condition wait (`waitFor`), and the end of the run loop turn's
//  undo group (`undoGroupsClosed`). Work that has a hook (`settled()`,
//  `sizeSettled()`, a ManualClock) awaits that instead (T6, lint rule 9).
//

import Foundation
import Testing

/// Waits for `condition`, up to `seconds`, checking every `poll`. False if
/// it never held.
///
/// For work that lands a moment later with nothing to await: ink, which a
/// page takes in on a detached task (`InkCapture`), so it reaches
/// `onInkChanged` a moment after the stroke; PaperKit selecting what it
/// inserted; SwiftUI letting go of a view's state; StoreKit's answers.
///
/// By suspending, not by turning the run loop: the work comes back to
/// the main actor, and a test turning the run loop is still holding it
/// (AGENTS.md › Implementation requirements, `PageViewTests.waitFor`).
@MainActor
@discardableResult
func waitFor(
    _ condition: () -> Bool,
    seconds: TimeInterval = 3,
    poll: Duration = .milliseconds(10)
) async -> Bool {
    let end = Date(timeIntervalSinceNow: seconds)
    while !condition() && Date() < end {
        try? await Task.sleep(for: poll)
    }
    return condition()
}

/// Returns once UIKit has closed the undo groups it opened in this turn of
/// the run loop. Each tap in the app is its own turn, and so its own undo
/// step: an undo manager that `groupsByEvent` opens a group at the first
/// edit of a turn and closes it as the turn ends. A test makes its edits back
/// to back, in one turn, and a single undo would take them all; this lets
/// the turn end in between. At once when no group is open; a group still
/// open after a second (one a test began itself) fails the test.
@MainActor
func undoGroupsClosed(_ managers: UndoManager?..., sourceLocation: SourceLocation = #_sourceLocation) async {
    let closed = await waitFor({ managers.allSatisfy { ($0?.groupingLevel ?? 0) == 0 } }, seconds: 1)
    #expect(closed, "an undo group stayed open", sourceLocation: sourceLocation)
}
