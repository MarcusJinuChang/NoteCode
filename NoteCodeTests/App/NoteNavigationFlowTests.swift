//
//  NoteNavigationFlowTests.swift
//  NoteCodeTests
//
//  T5 for 2P4 (refactor 2P-page.md): the flows around `NoteNavigation` that
//  NoteNavigationTests doesn't pin. Navigation through Home, the list and a
//  note in a compact stack; where a new note is filed; and delete with Undo
//  from the note and from the list, including what each Undo reopens when
//  the reader has moved on, and when toasts replace one another.
//  They pin today's behaviour, including the two Undos that differ.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import NoteCode

@Suite("Note navigation flows", .tags(.library))
@MainActor
struct NoteNavigationFlowTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func note(_ title: String, in folder: Folder? = nil) -> Page {
        let page = Page(title: title, content: "text of \(title)")
        context.insert(page)
        page.folder = folder
        return page
    }

    // MARK: Navigation

    @Test("A navigation starts on Home with the list beside it and nothing pushed")
    func startsOnHome() {
        let nav = NoteNavigation()
        #expect(nav.selection == nil)
        #expect(nav.columnVisibility == .all)
        #expect(nav.compactPath.isEmpty)
        #expect(nav.newPage == nil)
        #expect(nav.openedSearch == NoteSearch(""))
    }

    @Test("In a compact width: Home, the list, a note, and back, by the stack's rules")
    func compactRoundTrip() {
        let nav = NoteNavigation()
        nav.compactPath = [.list]
        nav.selection = note("A")
        nav.compactPath = CompactScreen.path(nav.compactPath, noteOpen: nav.selection != nil)
        #expect(nav.compactPath == [.list, .note])
        nav.selection = nil
        nav.compactPath = CompactScreen.path(nav.compactPath, noteOpen: false)
        #expect(nav.compactPath == [.list])
        #expect(CompactScreen.listShowing(in: nav.compactPath))
    }

    @Test("A note opened from Home sits on an empty stack, and closes back to Home")
    func homeToNoteAndBack() {
        let nav = NoteNavigation()
        nav.selection = note("A")
        nav.compactPath = CompactScreen.path(nav.compactPath, noteOpen: true)
        #expect(nav.compactPath == [.note])
        nav.selection = nil
        nav.compactPath = CompactScreen.path(nav.compactPath, noteOpen: false)
        #expect(nav.compactPath.isEmpty)
    }

    @Test("In a regular width, Home shows the list and an open note does not")
    func sidebarPlan() {
        #expect(SidebarPlan.showsList(noteOpen: false, storageFailed: false))
        #expect(!SidebarPlan.showsList(noteOpen: true, storageFailed: false))
        #expect(SidebarPlan.showsList(noteOpen: true, storageFailed: true))
    }

    // MARK: Create

    @Test("A note made while Home is up is unfiled and opens")
    func createFromHome() {
        let nav = NoteNavigation()
        let page = NoteActions(navigation: nav, context: context, toasts: nil).newNote(orientation: .default)
        #expect(page.folder == nil)
        #expect(nav.selection === page)
        #expect(page.isLive)
    }

    @Test("Making a second note moves the new-note mark to it and opens it")
    func createTwice() {
        let nav = NoteNavigation()
        let first = NoteActions(navigation: nav, context: context, toasts: nil).newNote(orientation: .default)
        let second = NoteActions(navigation: nav, context: context, toasts: nil).newNote(orientation: .default)
        #expect(first !== second)
        #expect(nav.newPage === second)
        #expect(nav.selection === second)
    }

    @Test("A note made while a deleted note is open is unfiled, not filed with it")
    func createFromDeletedNote() throws {
        let folder = Folder(name: "CS133")
        context.insert(folder)
        let open = note("Open", in: folder)
        let nav = NoteNavigation(selection: open)
        try Page.moveToRecentlyDeleted([open], from: context)

        let page = NoteActions(navigation: nav, context: context, toasts: nil).newNote(orientation: .default)
        #expect(page.folder == nil)
    }

    @Test("A template's note clears the search too, and is marked new")
    func createFromTemplate() {
        let nav = NoteNavigation()
        nav.openedSearch = NoteSearch("heap")
        let page = NoteActions(navigation: nav, context: context, toasts: nil).newNote(from: .lecture, orientation: .default)
        #expect(nav.newPage === page)
        #expect(nav.openedSearch == NoteSearch(""))
        #expect(nav.selection === page)
    }

    @Test("Making a note does not touch the stack or the columns; the views do that")
    func createLeavesLayoutAlone() {
        let nav = NoteNavigation(columnVisibility: .detailOnly, compactPath: [.list])
        NoteActions(navigation: nav, context: context, toasts: nil).newNote(orientation: .default)
        #expect(nav.compactPath == [.list])
        #expect(nav.columnVisibility == .detailOnly)
    }

    // MARK: Delete from the note

    @Test("Deleting from the note leaves it in Recently Deleted, saved")
    func deleteFromNoteIsSaved() throws {
        let toasts = ToastCenter()
        let page = note("Open")
        try context.save()
        let nav = NoteNavigation(selection: page)

        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([page], reopening: page)

        #expect(!page.isLive)
        #expect(!context.hasChanges, "moveToRecentlyDeleted saves at once")
        let deleted = try context.fetch(FetchDescriptor<Page>(predicate: Page.deletedPredicate))
        #expect(deleted.contains { $0 === page })
    }

    @Test("The note's Undo, with the reader on Home, reopens the note and clears the search")
    func deleteFromNoteUndoClearsSearch() {
        let toasts = ToastCenter()
        let page = note("Open")
        let nav = NoteNavigation(selection: page)
        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([page], reopening: page)
        nav.openedSearch = NoteSearch("stale")

        toasts.performAction()

        #expect(nav.selection === page)
        #expect(nav.openedSearch == NoteSearch(""))
        #expect(toasts.current == nil)
    }

    @Test("The note's Undo leaves the stack as the delete set it; the views' onChange pushes the note")
    func deleteFromNoteUndoLeavesStack() {
        let toasts = ToastCenter()
        let page = note("Open")
        let nav = NoteNavigation(selection: page, compactPath: [.note])
        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([page], reopening: page)
        toasts.performAction()
        #expect(nav.compactPath == [.list])
        #expect(nav.selection === page)
    }

    @Test("Deleting a note that is not the open one still closes the open one")
    func deleteFromNoteClosesWhateverIsOpen() {
        let toasts = ToastCenter()
        let open = note("Open")
        let other = note("Other")
        let nav = NoteNavigation(selection: open)
        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([other], reopening: other)
        #expect(nav.selection == nil)
        #expect(open.isLive)
    }

    // MARK: Delete from the list

    @Test("Deleting one note from the list names no count, and shows Undo")
    func deleteOneFromList() {
        let toasts = ToastCenter()
        let page = note("A")
        NoteActions(navigation: NoteNavigation(), context: context, toasts: toasts).moveToRecentlyDeleted([page])
        #expect(toasts.current?.message == "Moved to Recently Deleted")
        #expect(toasts.current?.action?.title == "Undo")
    }

    @Test("The list's Undo with the open note untouched leaves it open")
    func listUndoLeavesOpenNote() {
        let toasts = ToastCenter()
        let open = note("Open")
        let other = note("Other")
        let nav = NoteNavigation(selection: open)
        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([other])
        toasts.performAction()
        #expect(other.isLive)
        #expect(nav.selection === open)
    }

    @Test("The list's Undo does not reopen the note it closed")
    func listUndoNeverReopens() {
        let toasts = ToastCenter()
        let open = note("Open")
        let nav = NoteNavigation(selection: open)
        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([open])
        #expect(nav.selection == nil)
        toasts.performAction()
        #expect(open.isLive)
        #expect(nav.selection == nil)
    }

    @Test("The list's delete is saved and changes neither the stack nor the columns")
    func listDeleteLeavesLayout() throws {
        let toasts = ToastCenter()
        let page = note("A")
        try context.save()
        let nav = NoteNavigation(selection: page, columnVisibility: .detailOnly, compactPath: [.list, .note])
        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([page])
        #expect(!context.hasChanges)
        #expect(nav.compactPath == [.list, .note], "the view's onChange pops the stack")
        #expect(nav.columnVisibility == .detailOnly)
    }

    @Test("Without a toast centre the list still deletes, and says nothing")
    func listDeleteWithoutToasts() {
        let page = note("A")
        NoteActions(navigation: NoteNavigation(), context: context, toasts: nil).moveToRecentlyDeleted([page])
        #expect(!page.isLive)
    }

    @Test("Deleting a note already in Recently Deleted keeps its first date")
    func deleteKeepsFirstDate() {
        let toasts = ToastCenter()
        let page = note("A")
        let long = Date(timeIntervalSince1970: 1_000)
        page.deletedAt = long
        NoteActions(navigation: NoteNavigation(), context: context, toasts: toasts).moveToRecentlyDeleted([page])
        #expect(page.deletedAt == long)
    }

    // MARK: Two deletes

    @Test("A second delete replaces the first toast, and only the second Undo is left")
    func secondToastReplacesFirst() {
        let toasts = ToastCenter()
        let first = note("First")
        let second = note("Second")
        let nav = NoteNavigation()

        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([first])
        NoteActions(navigation: nav, context: context, toasts: toasts).moveToRecentlyDeleted([second])
        toasts.performAction()

        #expect(second.isLive)
        #expect(!first.isLive, "the first Undo is gone with its toast")
        toasts.performAction()
        #expect(!first.isLive, "nothing is left to undo")
    }

    @Test("The note's Undo and the list's differ: after the same delete one reopens and one does not")
    func theTwoUndosDiffer() {
        let toasts = ToastCenter()
        let fromNote = note("FromNote")
        let fromList = note("FromList")

        let noteNav = NoteNavigation(selection: fromNote)
        NoteActions(navigation: noteNav, context: context, toasts: toasts).moveToRecentlyDeleted([fromNote], reopening: fromNote)
        toasts.performAction()

        let listNav = NoteNavigation(selection: fromList)
        NoteActions(navigation: listNav, context: context, toasts: toasts).moveToRecentlyDeleted([fromList])
        toasts.performAction()

        #expect(noteNav.selection === fromNote)
        #expect(listNav.selection == nil)
    }

    // MARK: Folders

    @Test("Deleting a folder and keeping its notes shows no toast and closes nothing")
    func deleteFolderKeepingNotes() {
        let toasts = ToastCenter()
        let folder = Folder(name: "Old")
        context.insert(folder)
        let inside = note("Inside", in: folder)
        let nav = NoteNavigation(selection: inside)

        NoteActions(navigation: nav, context: context, toasts: toasts).delete(folder, .keepingNotes)

        #expect(nav.selection === inside)
        #expect(inside.isLive)
        #expect(inside.folder == nil)
        #expect(toasts.current == nil)
    }

    @Test("A folder's Undo brings its notes back with it, without reopening the open one")
    func folderUndoRestoresNotes() {
        let toasts = ToastCenter()
        let folder = Folder(name: "Old")
        context.insert(folder)
        let inside = note("Inside", in: folder)
        let nav = NoteNavigation(selection: inside)

        NoteActions(navigation: nav, context: context, toasts: toasts).delete(folder, .withNotes)
        #expect(!inside.isLive)
        toasts.performAction()

        #expect(folder.isLive)
        #expect(inside.isLive)
        #expect(nav.selection == nil)
    }
}
