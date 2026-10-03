//
//  SchemaMigrationTests.swift
//  NoteCodeTests
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

/// Notes written before folders existed have to open after.
///
/// Each test writes a store on disk with the model as it was before versions
/// (`NoteSchemaV1`, opened without a version, the way every build before
/// 3 October 2026 opened it), then opens it the way the app does now. A store
/// that fails to migrate doesn't crash: `Storage` falls back to memory, and
/// the notes look gone. So these check `Storage` itself, not a container
/// opened some other way.
@Suite("Migrating the store")
@MainActor
struct SchemaMigrationTests {

    /// A folder of its own per test: the store, its write-ahead log, and the
    /// external storage folder ink goes in all sit next to each other.
    private let directory: URL
    private var storeURL: URL { directory.appending(path: "notes.store") }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "SchemaMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Big enough that SwiftData keeps it outside the store's records, the
    /// way real ink is kept.
    private static let ink = Data((0..<300_000).map { UInt8($0 % 251) })

    /// Writes a store the way builds before versions did, and closes it.
    private func writeUnversionedStore() throws {
        let schema = Schema([NoteSchemaV1.Page.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let context = ModelContext(container)

        let drawn = NoteSchemaV1.Page(
            title: "Lecture 1",
            content: "# Pointers\n```cpp\nint *p;\n```\n",
            drawingData: Self.ink,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        drawn.runDestination = "godbolt"
        drawn.pageOrientation = "landscape"
        drawn.modifiedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(drawn)

        context.insert(NoteSchemaV1.Page(title: "Plain", createdAt: Date(timeIntervalSince1970: 3_000)))
        try context.save()
    }

    private func openedNotes(_ storage: Storage) throws -> [Page] {
        let container = try #require(storage.container)
        return try ModelContext(container).fetch(
            FetchDescriptor<Page>(sortBy: [SortDescriptor(\.createdAt)])
        )
    }

    @Test("Notes from before folders open with everything they had")
    func unversionedStoreMigrates() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeUnversionedStore()

        let storage = Storage.open(at: storeURL)

        #expect(storage.reason == nil)
        #expect(storage.isEphemeral == false)

        let notes = try openedNotes(storage)
        #expect(notes.map(\.title) == ["Lecture 1", "Plain"])

        let drawn = try #require(notes.first)
        #expect(drawn.content == "# Pointers\n```cpp\nint *p;\n```\n")
        #expect(drawn.drawingData == Self.ink)
        #expect(drawn.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(drawn.modifiedAt == Date(timeIntervalSince1970: 2_000))
        #expect(drawn.runDestination == "godbolt")
        #expect(drawn.orientation == .landscape)

        // What the new version adds starts empty.
        #expect(notes.allSatisfy { $0.folder == nil && !$0.isPinned })
        #expect(notes[1].drawingData.isEmpty)
        #expect(notes[1].orientation == .portrait)
    }

    @Test("A migrated store keeps folders across a relaunch")
    func foldersSurviveRelaunch() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeUnversionedStore()

        do {
            let storage = Storage.open(at: storeURL)
            let container = try #require(storage.container)
            let context = ModelContext(container)
            let notes = try context.fetch(FetchDescriptor<Page>(sortBy: [SortDescriptor(\.createdAt)]))

            let cs133 = Folder(name: "CS133")
            context.insert(cs133)
            notes[0].folder = cs133
            notes[0].isPinned = true
            try context.save()
        }

        let relaunched = try openedNotes(Storage.open(at: storeURL))
        #expect(relaunched[0].folder?.name == "CS133")
        #expect(relaunched[0].isPinned)
        #expect(relaunched[1].folder == nil)
    }
}
