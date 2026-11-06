//
//  NoteNavigation.swift
//  NoteCode
//
//  What the window has open, and the actions that change it: making a note
//  and moving one to Recently Deleted, with their toasts.
//

import SwiftData
import SwiftUI

/// The window's navigation state and the create and delete actions that move it.
///
/// This is the seam 2P4 needed (refactor 2P-page.md, route A): `ContentView`
/// and `NoteList` used to keep this in private view state, where no test could
/// drive it. The views hold one of these and call it; the `ToastCenter`, the
/// `ModelContext` and anything read from settings (the new-note orientation)
/// are passed in, so a test can supply its own. Nothing here is new behaviour:
/// each method is the body of the view method it replaced.
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

    // MARK: Create

    /// ⌘N and the + button's tap: a note in the open note's folder, opened
    /// with its title ready to rename, through `Page.create` like every other
    /// way of making one.
    @discardableResult
    func newNote(orientation: PageOrientation, context: ModelContext) -> Page {
        let page = Page.create(
            orientation: orientation,
            in: NewNotes.folder(whileViewing: selection),
            context: context
        )
        open(newlyMade: page)
        return page
    }

    /// A note from a template, made and opened the way ⌘N makes one.
    @discardableResult
    func newNote(from template: NoteTemplate, orientation: PageOrientation, context: ModelContext) -> Page {
        let page = Page.create(
            from: template,
            orientation: orientation,
            in: NewNotes.folder(whileViewing: selection),
            context: context
        )
        open(newlyMade: page)
        return page
    }

    private func open(newlyMade page: Page) {
        newPage = page
        openedSearch = NoteSearch("")
        selection = page
    }

    // MARK: Delete

    /// Closes the open note and moves it to Recently Deleted.
    ///
    /// The note closes first, and the page that shows it with it. The list
    /// comes back, since the page it slid away for is gone and its ☰ with it.
    /// Nothing asks: the toast's Undo puts the note back and, if the reader
    /// hasn't opened another since, reopens it.
    func delete(_ page: Page, context: ModelContext, toasts: ToastCenter) {
        selection = nil
        // In the stack, back to the list, as the split view brings it over.
        compactPath = [.list]
        withAnimation {
            columnVisibility = .all
            // If saving fails, the change is still pending in the context,
            // and autosave tries again.
            try? Page.moveToRecentlyDeleted([page], from: context)
        }
        toasts.show("Moved to Recently Deleted", actionTitle: "Undo") { [self] in
            withAnimation { try? Page.restore([page], in: context) }
            if selection == nil {
                openedSearch = NoteSearch("")
                selection = page
            }
        }
    }

    /// The list's delete: moves notes to Recently Deleted, with a toast that
    /// puts them back. If the open note is among them it closes, and Undo
    /// restores without reopening it.
    func deletePages(_ deleted: [Page], context: ModelContext, toasts: ToastCenter?) {
        if let selection, deleted.contains(selection) {
            self.selection = nil
        }
        withAnimation {
            // If saving fails, the change is still pending in the context,
            // and autosave tries again.
            try? Page.moveToRecentlyDeleted(deleted, from: context)
        }
        guard !deleted.isEmpty, let toasts else { return }
        toasts.show(
            deleted.count == 1 ? "Moved to Recently Deleted" : "Moved \(deleted.count) notes to Recently Deleted",
            actionTitle: "Undo"
        ) {
            withAnimation { try? Page.restore(deleted, in: context) }
        }
    }

    /// The list's folder delete. Notes in it go to Recently Deleted with it,
    /// or are kept, by `deletion`.
    func delete(_ folder: Folder, _ deletion: Folder.Deletion, context: ModelContext, toasts: ToastCenter?) {
        // Only the notes the reader could see go to Recently Deleted; the ones
        // already there keep their first date.
        let going = deletion == .withNotes ? folder.livePages : []
        // The open note closes first if it's going.
        if let selection, going.contains(selection) {
            self.selection = nil
        }
        withAnimation {
            try? Folder.delete(folder, deletion, from: context)
        }
        // Kept notes leave a folder that is gone for good, so there is nothing
        // to undo. Deleted ones went with the folder, and Undo brings both back.
        guard deletion == .withNotes, let toasts else { return }
        toasts.show("Moved “\(folder.name)” to Recently Deleted", actionTitle: "Undo") {
            withAnimation { try? Folder.restore([folder], in: context) }
        }
    }
}
