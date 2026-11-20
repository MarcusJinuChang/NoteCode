//
//  ModifiedAtBatcher.swift
//  NoteCode
//
//  When a note's `modifiedAt` is written while it is typed in. It is the
//  list's `@Query` sort key, so a write per keystroke re-sorted every live
//  list as the reader typed (F6). The text is saved as it always was; only
//  the timestamp waits, until typing pauses, the note closes or the app
//  leaves the screen.
//

import Foundation
import SwiftData

@MainActor
final class ModifiedAtBatcher {

    /// How long typing must pause before the date is written.
    static let pause: Duration = .seconds(2)

    /// When the last edit not yet written to the page was made.
    private(set) var pendingEdit: Date?
    private weak var page: Page?
    private var timer: Task<Void, Never>?

    /// The note was edited: its date is written once `pause` passes with no
    /// further edit, measured on `clock` (`EnvironmentValues.debounceClock`).
    func edited(_ page: Page, clock: any Clock<Duration>) {
        // The same view showing another note: the first one's edit is owed.
        if let held = self.page, held !== page { flush() }
        self.page = page
        pendingEdit = .now
        timer?.cancel()
        timer = Task { [weak self] in
            try? await clock.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes the owed date now: the note closing, or the app leaving the screen.
    func flush() {
        timer?.cancel()
        timer = nil
        guard let date = pendingEdit else { return }
        pendingEdit = nil
        // A deleted note has no list row left to move, and nothing to write to.
        guard let page, page.modelContext != nil, !page.isDeleted else { return }
        page.modifiedAt = date
    }

    /// Returns once the pause has run its course, for tests.
    func settled() async {
        await timer?.value
    }
}
