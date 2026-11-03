//
//  NoteMemoryTests.swift
//  NoteCodeTests
//
//  Phase 2 of v3: what the device remembers about notes.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Note memory")
@MainActor
struct NoteMemoryTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    /// A defaults of its own, so a test can't read what another wrote or the
    /// simulator's real settings.
    private func freshDefaults() -> UserDefaults {
        let name = "NoteMemoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func savedPage(_ title: String = "Note") throws -> Page {
        let page = Page(title: title)
        context.insert(page)
        try context.save()
        return page
    }

    @Test("The same ID gives the same key every time")
    func keyIsStable() throws {
        let page = try savedPage()
        let id = try #require(page.settledID)
        let keys = Set((0..<200).compactMap { _ in NoteMemory.key(for: id) })
        #expect(keys.count == 1, "\(keys.count) different keys for one note")
    }

    @Test("A note not yet saved has a temporary ID, which can't be remembered, until it is saved")
    func temporaryIDs() throws {
        let page = Page(title: "New")
        context.insert(page)
        #expect(NoteMemory.key(for: page.persistentModelID) == nil)

        let id = try #require(page.settledID, "settledID saves a note that has no permanent ID yet")
        #expect(!id.isTemporary)
        #expect(NoteMemory.key(for: id) != nil)
    }

    @Test("The last-opened note comes back as the note, and survives another note being remembered after")
    func lastOpened() throws {
        let defaults = freshDefaults()
        let memory = NoteMemory(defaults: defaults)
        #expect(memory.lastOpenedKey() == nil)

        let first = try savedPage("First")
        let second = try savedPage("Second")
        memory.rememberOpened(first)
        #expect(memory.lastOpenedKey() == NoteMemory.key(for: first.persistentModelID))
        memory.rememberOpened(second)
        #expect(memory.lastOpenedKey() == NoteMemory.key(for: second.persistentModelID))
    }

    @Test("A place is kept per note, and a note with none has none")
    func places() throws {
        let memory = NoteMemory(defaults: freshDefaults())
        let a = try savedPage("A")
        let b = try savedPage("B")
        let idA = try #require(a.settledID)
        let idB = try #require(b.settledID)

        #expect(memory.place(of: idA) == nil)
        memory.setPlace(.init(page: 2, of: 5), of: idA)
        memory.setPlace(.init(page: 0, of: 1), of: idB)
        #expect(memory.place(of: idA) == .init(page: 2, of: 5))
        #expect(memory.place(of: idB) == .init(page: 0, of: 1))
        #expect(memory.place(of: idA)?.number == 3)

        memory.setPlace(.init(page: 4, of: 7), of: idA)
        #expect(memory.place(of: idA) == .init(page: 4, of: 7), "a later place replaces the earlier one")
    }

    @Test("Nothing is stored for a temporary ID")
    func temporaryIDStoresNothing() {
        let memory = NoteMemory(defaults: freshDefaults())
        let page = Page(title: "New")
        context.insert(page)
        memory.setPlace(.init(page: 1, of: 2), of: page.persistentModelID)
        memory.setLastOpened(page.persistentModelID)
        #expect(memory.lastOpenedKey() == nil)
    }

    @Test("A stored value that isn't a place is ignored, never trapped on")
    func badValues() throws {
        let defaults = freshDefaults()
        let memory = NoteMemory(defaults: defaults)
        let page = try savedPage()
        let id = try #require(page.settledID)
        let key = try #require(NoteMemory.key(for: id))

        for pair in [[1], [1, 2, 3], [-1, 4], [0, 0]] {
            defaults.set([key: pair], forKey: NoteMemory.placesKey)
            #expect(memory.place(of: id) == nil, "\(pair)")
        }
    }

    @Test("Pruning forgets the places of notes that are gone, and keeps the rest")
    func pruning() throws {
        let defaults = freshDefaults()
        let memory = NoteMemory(defaults: defaults)
        let kept = try savedPage("Kept")
        let gone = try savedPage("Gone")
        let keptID = try #require(kept.settledID)
        let goneID = try #require(gone.settledID)
        memory.setPlace(.init(page: 1, of: 3), of: keptID)
        memory.setPlace(.init(page: 2, of: 4), of: goneID)
        memory.setLastOpened(goneID)

        memory.prune(keeping: [keptID])

        #expect(memory.place(of: keptID) == .init(page: 1, of: 3))
        #expect(memory.place(of: goneID) == nil)
        #expect(memory.lastOpenedKey() == nil, "the last-opened note is gone too")
    }

    @Test("Pruning with the IDs the store reports keeps the places of the notes it holds")
    func pruningWithFetchedIdentifiers() throws {
        let memory = NoteMemory(defaults: freshDefaults())
        let page = try savedPage()
        let id = try #require(page.settledID)
        memory.setPlace(.init(page: 1, of: 3), of: id)
        memory.setLastOpened(id)

        let fetched = Set(try context.fetchIdentifiers(FetchDescriptor<Page>()))
        #expect(fetched.contains(id), "the store's ID for the note is the note's own")
        memory.prune(keeping: fetched)

        #expect(memory.place(of: id) == .init(page: 1, of: 3))
        #expect(memory.lastOpenedKey() == NoteMemory.key(for: id))
    }

    @Test("The keys are pinned: renaming one orphans what a device saved")
    func keysArePinned() {
        #expect(NoteMemory.lastOpenedKey == "lastOpenedNote")
        #expect(NoteMemory.placesKey == "notePlaces")
        #expect(WelcomeScreen.shownKey == "welcomeScreenShown")
    }
}
