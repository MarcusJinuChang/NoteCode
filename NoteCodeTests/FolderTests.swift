//
//  FolderTests.swift
//  NoteCodeTests
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Folders")
@MainActor
struct FolderTests {

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
        let page = Page(title: title)
        context.insert(page)
        page.folder = folder
        return page
    }

    private func folder(_ name: String) -> Folder {
        let folder = Folder(name: name)
        context.insert(folder)
        return folder
    }

    /// What a relaunch would see: a context of its own reads only what the
    /// store has.
    private func titlesInStore() throws -> Set<String> {
        Set(try ModelContext(container).fetch(FetchDescriptor<Page>()).map(\.title))
    }

    // MARK: Naming

    @Test("A typed name is trimmed, and a blank one gets a name anyway")
    func typedNames() {
        #expect(Folder.name(fromTyped: "  CS133 \n") == "CS133")
        #expect(Folder.name(fromTyped: "   ") == "Untitled Folder")
        #expect(Folder.name(fromTyped: "") == "Untitled Folder")
    }

    // MARK: The list

    @Test("Folders are in name order, numbers compared as numbers")
    func folderOrder() {
        let folders = [folder("CS 133"), folder("algorithms"), folder("CS 9")]

        let sections = NoteListSections(pages: [], folders: folders)

        #expect(sections.folders.map(\.folder.name) == ["algorithms", "CS 9", "CS 133"])
    }

    @Test("Notes go under their folder, in the order given, and the rest stay at the top")
    func notesAreGrouped() {
        let cs133 = folder("CS133")
        let empty = folder("Empty")
        let newest = note("Newest", in: cs133)
        let loose = note("Loose")
        let oldest = note("Oldest", in: cs133)

        let sections = NoteListSections(pages: [newest, loose, oldest], folders: [empty, cs133])

        #expect(sections.folders.map(\.folder.name) == ["CS133", "Empty"])
        #expect(sections.folders[0].notes.map(\.title) == ["Newest", "Oldest"])
        #expect(sections.folders[1].notes.isEmpty)
        #expect(sections.unfiled.map(\.title) == ["Loose"])
    }

    // MARK: Deleting

    @Test("Deleting a folder but not its notes leaves them at the top, and saves")
    func deleteKeepingNotes() throws {
        let cs133 = folder("CS133")
        let lecture = note("Lecture 1", in: cs133)
        try context.save()

        try Folder.delete(cs133, .keepingNotes, from: context)

        #expect(try titlesInStore() == ["Lecture 1"])
        #expect(lecture.folder == nil)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Folder>()).isEmpty)
    }

    @Test("Deleting a folder with its notes deletes only those, and saves")
    func deleteWithNotes() throws {
        let cs133 = folder("CS133")
        _ = note("Lecture 1", in: cs133)
        _ = note("Lecture 2", in: cs133)
        _ = note("Loose")
        try context.save()

        try Folder.delete(cs133, .withNotes, from: context)

        #expect(try titlesInStore() == ["Loose"])
    }

    @Test("Deleting a note takes it out of its folder")
    func deletingNoteLeavesFolder() throws {
        let cs133 = folder("CS133")
        let kept = note("Kept", in: cs133)
        let deleted = note("Deleted", in: cs133)
        try context.save()

        try Page.delete([deleted], from: context)

        #expect(cs133.pages?.map(\.title) == [kept.title])
    }

    // MARK: Run destination

    @Test("A note runs where it chose, then where its folder chose, then the default")
    func runDestinationLevels() {
        let cs133 = folder("CS133")
        let page = note("Lecture", in: cs133)
        let appDefault = CodeDestination.programiz.id

        func resolved() -> CodeDestination {
            RunDestinationPreference.resolve(page.runDestinationLevels(appDefault: appDefault))
        }

        #expect(resolved() == .programiz)

        cs133.runDestination = CodeDestination.compilerExplorer.id
        #expect(resolved() == .compilerExplorer)

        page.runDestination = CodeDestination.onlineGDB.id
        #expect(resolved() == .onlineGDB)

        page.runDestination = nil
        page.folder = nil
        #expect(resolved() == .programiz)
    }

    @Test("A folder setting nothing recognises is passed over")
    func unknownFolderDestination() {
        let cs133 = folder("CS133")
        cs133.runDestination = "from-a-newer-build"
        let page = note("Lecture", in: cs133)

        let levels = page.runDestinationLevels(appDefault: CodeDestination.onlineGDB.id)

        #expect(RunDestinationPreference.resolve(levels) == .onlineGDB)
    }
}
