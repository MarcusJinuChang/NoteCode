//
//  StorageTests.swift
//  NoteCodeTests
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Storage")
@MainActor
struct StorageTests {

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Page.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    @Test("Opening storage yields a usable container")
    func openSucceeds() {
        let storage = Storage.open()

        #expect(storage.container != nil)
        #expect(storage.isEphemeral == false)
        #expect(storage.reason == nil)
    }

    @Test("A persistent store is not flagged as ephemeral")
    func persistentIsNotEphemeral() throws {
        let storage = Storage.persistent(try inMemoryContainer())

        #expect(storage.container != nil)
        #expect(storage.isEphemeral == false)
        #expect(storage.reason == nil)
    }

    @Test("An ephemeral store still hands back a container, and says why")
    func ephemeralStillUsable() throws {
        // The important case: the app keeps working when the disk store fails,
        // but the UI has to be able to warn that edits won't survive.
        let storage = Storage.ephemeral(try inMemoryContainer(), reason: "disk full")

        #expect(storage.container != nil)
        #expect(storage.isEphemeral)
        #expect(storage.reason == "disk full")
    }

    @Test("An unavailable store has no container but explains itself")
    func unavailableExplainsItself() {
        let storage = Storage.unavailable(reason: "store corrupted")

        #expect(storage.container == nil)
        #expect(storage.isEphemeral == false)
        #expect(storage.reason == "store corrupted")
    }

    @Test("Deleting a note reaches the store at once, not at the next autosave")
    func deletionIsSaved() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let kept = Page(title: "Kept")
        let deleted = Page(title: "Deleted")
        context.insert(kept)
        context.insert(deleted)
        try context.save()

        try Page.delete([deleted], from: context)

        // A context of its own sees only what the store has: what a relaunch
        // would see. Only the main context autosaves, so this one never does.
        let relaunched = ModelContext(container)
        let titles = try relaunched.fetch(FetchDescriptor<Page>()).map(\.title)
        #expect(titles == ["Kept"])
    }
}
