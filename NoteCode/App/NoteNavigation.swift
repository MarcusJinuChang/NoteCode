//
//  NoteNavigation.swift
//  NoteCode
//
//  What the window has open. Making a note and moving one to Recently Deleted
//  are `NoteActions`.
//

import SwiftData
import SwiftUI

/// The window's navigation state: the open note, the split view's columns,
/// the compact stack and the search the note was opened from (2P4's
/// `NavigationModel`).
///
/// `ContentView` and `NoteList` used to keep this in private view state,
/// where no test could drive it. The views hold one of these; `NoteActions`
/// changes it.
@MainActor
@Observable
final class NoteNavigation {
    /// The open note; nil is Home.
    var selection: Page?

    /// The split view's columns. The list is away over a note and back on Home.
    var columnVisibility: NavigationSplitViewVisibility

    /// In a compact width, what is pushed (`CompactScreen`).
    var compactPath: [CompactScreen]

    /// The search the open note was opened from, so it can show where it
    /// matched.
    var openedSearch = NoteSearch("")

    /// A note the reader has just made, which opens with its title being
    /// renamed. Cleared when another note opens.
    var newPage: Page?

    init(
        selection: Page? = nil,
        columnVisibility: NavigationSplitViewVisibility = .all,
        compactPath: [CompactScreen] = []
    ) {
        self.selection = selection
        self.columnVisibility = columnVisibility
        self.compactPath = compactPath
    }

    /// Opens a note just made: its title is renamed, and no search is behind it.
    func open(newlyMade page: Page) {
        newPage = page
        openedSearch = NoteSearch("")
        selection = page
    }
}
