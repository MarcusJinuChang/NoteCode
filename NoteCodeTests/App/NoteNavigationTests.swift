//
//  NoteNavigationTests.swift
//  NoteCodeTests
//
//  The seam 2P4 added (2P-page.md, route A): creating and deleting through the
//  object the views hold, with a ToastCenter and a context of the test's own.
//  These pin today's behaviour, including the two Undos that differ.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import NoteCode

@Suite("Note navigation", .tags(.library))
@MainActor
struct NoteNavigationTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func note(_ title: String) -> Page {
        let page = Page(title: title, content: "text of \(title)")
        context.insert(page)
        return page
    }

    @Test("A new note opens, ready to rename, and clears the search it was opened from")
    func create() {
        let nav = NoteNavigation()
        nav.openedSearch = NoteSearch("loop")

        let page = NoteActions(navigation: nav, context: context, toasts: nil).newNote(orientation: .default)

        #expect(nav.selection === page)
        #expect(nav.newPage === page)
        #expect(nav.openedSearch == NoteSearch(""))
    }

    @Test("A new note lands in the open note's folder, and a template's note too")
    func createInFolder() {
        let folder = Folder(name: "CS133")
        context.insert(folder)
        let open = note("Open")
        open.folder = folder
        let nav = NoteNavigation(selection: open)

        let plain = NoteActions(navigation: nav, context: context, toasts: nil).newNote(orientation: .default)
        #expect(plain.folder === folder)

        let templated = NoteActions(navigation: nav, context: context, toasts: nil).newNote(from: .lecture, orientation: .default)
        #expect(templated.folder === folder)
        #expect(templated.title == NoteTemplate.lecture.title)
        #expect(nav.selection === templated)
    }

    @Test("Deleting from the note closes it, shows the list, and its Undo reopens the note")
    func deleteFromNoteUndoReopens() {
        let toasts = ToastCenter()
        let page = note("Open")
        let nav = NoteNavigation(selection: page, columnVisibility: .detailOnly, compactPath: [.note])

        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([page], reopening: page)

        #expect(nav.selection == nil)
        #expect(nav.compactPath == [.list])
        #expect(nav.columnVisibility == .all)
        #expect(page.deletedAt != nil)
        #expect(toasts.current?.message == "Moved to Recently Deleted")
        #expect(toasts.current?.action?.title == "Undo")

        toasts.performAction()
        #expect(page.deletedAt == nil)
        #expect(nav.selection === page)
    }

    @Test("The note's Undo does not take the reader from a note they opened since")
    func deleteFromNoteUndoKeepsOtherNote() {
        let toasts = ToastCenter()
        let page = note("Deleted")
        let other = note("Other")
        let nav = NoteNavigation(selection: page)

        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([page], reopening: page)
        nav.selection = other
        toasts.performAction()

        #expect(page.deletedAt == nil)
        #expect(nav.selection === other)
    }

    @Test("Deleting from the list closes the open note if it is among them, and Undo restores without reopening")
    func deleteFromListUndoRestoresOnly() {
        let toasts = ToastCenter()
        let open = note("Open")
        let beside = note("Beside")
        let nav = NoteNavigation(selection: open)

        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([open, beside])

        #expect(nav.selection == nil)
        #expect(open.deletedAt != nil && beside.deletedAt != nil)
        #expect(toasts.current?.message == "Moved 2 notes to Recently Deleted")

        toasts.performAction()
        #expect(open.deletedAt == nil && beside.deletedAt == nil)
        #expect(nav.selection == nil, "the list's Undo restores and does not reopen")
    }

    @Test("Deleting a note from the list that is not open leaves the open note")
    func deleteFromListKeepsOpen() {
        let toasts = ToastCenter()
        let open = note("Open")
        let other = note("Other")
        let nav = NoteNavigation(selection: open)

        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([other])

        #expect(nav.selection === open)
        #expect(toasts.current?.message == "Moved to Recently Deleted")
    }

    @Test("Deleting nothing shows no toast")
    func deleteNothing() {
        let toasts = ToastCenter()
        NoteActions(navigation: NoteNavigation(), context: context, toasts: toasts).moveToRecentlyDeleted([])
        #expect(toasts.current == nil)
    }

    @Test("A folder deleted with its notes closes the open note, and Undo brings the folder back")
    func deleteFolder() {
        let toasts = ToastCenter()
        let folder = Folder(name: "Old")
        context.insert(folder)
        let inside = note("Inside")
        inside.folder = folder
        let nav = NoteNavigation(selection: inside)

        NoteActions(navigation: nav, context: context, toasts: toasts).delete(folder, .withNotes)

        #expect(nav.selection == nil)
        #expect(toasts.current?.message == "Moved “Old” to Recently Deleted")

        toasts.performAction()
        #expect(folder.deletedAt == nil)
    }
}
