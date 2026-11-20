//
//  NoteActions.swift
//  NoteCode
//
//  Making a note and moving one to Recently Deleted, with their toasts: one
//  set of actions for ContentView and the note list.
//

import SwiftData
import SwiftUI

/// The create and delete actions that move `NoteNavigation`.
///
/// The `ModelContext`, the `ToastCenter` and anything read from settings (the
/// new-note orientation) are passed in, so a test can supply its own. Each
/// method is the body of the view method it replaced; nothing is new
/// behaviour.
@MainActor
struct NoteActions {
    let navigation: NoteNavigation
    let context: ModelContext
    /// Nil where no toast can be shown (the list outside a window).
    let toasts: ToastCenter?

    // MARK: Create

    /// ⌘N and the + button's tap: a note in the open note's folder, opened
    /// with its title ready to rename, through `Page.create` like every other
    /// way of making one.
    @discardableResult
    func newNote(orientation: PageOrientation) -> Page {
        let page = Page.create(
            orientation: orientation,
            in: NewNotes.folder(whileViewing: navigation.selection),
            context: context
        )
        navigation.open(newlyMade: page)
        return page
    }

    /// A note from a template, made and opened the way ⌘N makes one.
    @discardableResult
    func newNote(from template: NoteTemplate, orientation: PageOrientation) -> Page {
        let page = Page.create(
            from: template,
            orientation: orientation,
            in: NewNotes.folder(whileViewing: navigation.selection),
            context: context
        )
        navigation.open(newlyMade: page)
        return page
    }

    // MARK: Delete

    /// Moves notes to Recently Deleted, with a toast whose Undo puts them
    /// back. The two callers differ and keep differing:
    ///
    /// - `reopening` is a page: the note's own ••• menu. The note closes
    ///   first, and the page that shows it with it. The list comes back,
    ///   since the page it slid away for is gone and its ☰ with it. Undo
    ///   restores and, if the reader hasn't opened another note since,
    ///   reopens it.
    /// - `reopening` is nil: the list's delete, one note or many. If the open
    ///   note is among them it closes, and Undo restores without reopening.
    ///
    /// Nothing asks. Saved at once (`Page.moveToRecentlyDeleted`).
    func moveToRecentlyDeleted(_ pages: [Page], reopening: Page? = nil) {
        let nav = navigation
        if reopening != nil {
            nav.selection = nil
            // In the stack, back to the list, as the split view brings it over.
            nav.compactPath = [.list]
        } else if let selection = nav.selection, pages.contains(selection) {
            nav.selection = nil
        }
        let context = context
        withAnimation {
            if reopening != nil { nav.columnVisibility = .all }
            // If saving fails, the change is still pending in the context,
            // and autosave tries again.
            Storage.attempt("move notes to Recently Deleted") { try Page.moveToRecentlyDeleted(pages, from: context) }
        }
        guard !pages.isEmpty, let toasts else { return }
        toasts.show(
            pages.count == 1 ? "Moved to Recently Deleted" : "Moved \(pages.count) notes to Recently Deleted",
            actionTitle: "Undo"
        ) {
            withAnimation { _ = Storage.attempt("restore notes") { try Page.restore(pages, in: context) } }
            if let reopening, nav.selection == nil {
                nav.openedSearch = NoteSearch("")
                nav.selection = reopening
            }
        }
    }

    /// The list's folder delete. Notes in it go to Recently Deleted with it,
    /// or are kept, by `deletion`.
    func delete(_ folder: Folder, _ deletion: Folder.Deletion) {
        // Only the notes the reader could see go to Recently Deleted; the ones
        // already there keep their first date.
        let going = deletion == .withNotes ? folder.livePages : []
        // The open note closes first if it's going.
        if let selection = navigation.selection, going.contains(selection) {
            navigation.selection = nil
        }
        let context = context
        withAnimation {
            _ = Storage.attempt("delete a folder") { try Folder.delete(folder, deletion, from: context) }
        }
        // Kept notes leave a folder that is gone for good, so there is nothing
        // to undo. Deleted ones went with the folder, and Undo brings both back.
        guard deletion == .withNotes, let toasts else { return }
        toasts.show("Moved “\(folder.name)” to Recently Deleted", actionTitle: "Undo") {
            withAnimation { _ = Storage.attempt("restore a folder") { try Folder.restore([folder], in: context) } }
        }
    }
}
