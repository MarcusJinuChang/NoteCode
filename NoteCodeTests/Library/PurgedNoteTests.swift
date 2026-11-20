//
//  PurgedNoteTests.swift
//  NoteCodeTests
//
//  AGENTS.md › Implementation requirements: never read `Page.drawingData`
//  from a page whose deletion has been saved (SwiftData traps), and a
//  deletion saves at once. T8 of the refactor plan.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Purged notes", .tags(.library))
@MainActor
struct PurgedNoteTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    /// A note with enough ink that the store keeps it outside the record.
    private func noteWithInk() throws -> Page {
        let page = Page(title: "Inked", content: "text", drawingData: Data(repeating: 7, count: 400_000))
        context.insert(page)
        try context.save()
        return page
    }

    /// The same note fetched into a context of its own, as a relaunch has it:
    /// its ink is not loaded, which is what makes reading it after the purge
    /// trap. (The context is returned because a page holds its context weakly.)
    private func unloadedNote() throws -> (page: Page, context: ModelContext) {
        _ = try noteWithInk()
        let fresh = ModelContext(container)
        let page = try #require(try fresh.fetch(FetchDescriptor<Page>()).first)
        return (page, fresh)
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PurgedNoteTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("A thumbnail asked for after the purge reads nothing and draws nothing")
    func thumbnailAfterPurge() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ThumbnailStore(directory: dir)
        let (page, fresh) = try unloadedNote()

        try Page.delete([page], from: fresh)

        #expect(await store.thumbnail(for: page) == nil)
        #expect(store.rendered == 0)
    }

    @Test("A note purged while its thumbnail waits for its turn is not read")
    func purgedWhileWaiting() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ThumbnailStore(directory: dir)
        let (page, fresh) = try unloadedNote()

        // The request starts and yields before it reads the note; the purge
        // lands in that gap.
        let asking = Task { @MainActor in await store.thumbnail(for: page) }
        await Task.yield()
        try Page.delete([page], from: fresh)

        #expect(await asking.value == nil)
        #expect(store.rendered == 0)
    }

    @Test("Moving a note to Recently Deleted reaches the store at once")
    func recentlyDeletedIsSavedAtOnce() throws {
        let page = Page(title: "Going")
        context.insert(page)
        try context.save()

        try Page.moveToRecentlyDeleted([page], from: context)

        // A context of its own sees only what the store has.
        let relaunched = ModelContext(container)
        let stored = try relaunched.fetch(FetchDescriptor<Page>())
        #expect(stored.count == 1)
        #expect(stored.first?.deletedAt != nil)
    }

    @Test("Purging from Recently Deleted reaches the store at once")
    func purgeIsSavedAtOnce() throws {
        let page = try noteWithInk()
        try Page.moveToRecentlyDeleted([page], from: context)

        try Page.delete([page], from: context)

        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Page>()) == 0)
    }
}
