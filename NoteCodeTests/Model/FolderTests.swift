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

    @Test("Deleting a folder with its notes moves only those to Recently Deleted, and saves")
    func deleteWithNotes() throws {
        let cs133 = folder("CS133")
        let one = note("Lecture 1", in: cs133)
        let two = note("Lecture 2", in: cs133)
        let loose = note("Loose")
        try context.save()

        try Folder.delete(cs133, .withNotes, from: context)

        // Nothing is deleted for good: the notes wait to be restored.
        #expect(try titlesInStore() == ["Lecture 1", "Lecture 2", "Loose"])
        let live = try ModelContext(container).fetch(FetchDescriptor<Page>()).live
        #expect(live.map(\.title) == ["Loose"])
        #expect(!one.isLive && !two.isLive && loose.isLive)
        // The folder waits there with them, and is out of every view meanwhile.
        let folders = try ModelContext(container).fetch(FetchDescriptor<Folder>())
        #expect(folders.count == 1 && folders.live.isEmpty)
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
}
