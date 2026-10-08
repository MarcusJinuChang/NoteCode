//
//  SchemaMigrationTests.swift
//  NoteCodeTests
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

/// Notes written by any earlier build have to open in this one.
///
/// Each test writes a store on disk with one of the shapes builds wrote
/// before versions existed (`NoteSchemaV1` to `NoteSchemaV4`, opened without
/// a version, the way those builds opened them), or with version 5, the
/// first written as a version, then opens it the way the app does now. A store that fails to migrate doesn't crash: `Storage` falls
/// back to memory, and the notes look gone. So these check `Storage` itself,
/// not a container opened some other way.
@Suite("Migrating the store")
@MainActor
struct SchemaMigrationTests {

    /// The shapes a store can have been written in, by the version that
    /// recognises them.
    enum EarlierShape: Int, CaseIterable, Sendable {
        case firstPage = 1
        case runDestination
        case pageOrientation
        case externalInk
    }

    /// A folder of its own per test: the store, its write-ahead log, and the
    /// external storage folder ink goes in all sit next to each other.
    private let directory: URL
    private var storeURL: URL { directory.appending(path: "notes.store") }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "SchemaMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Big enough that SwiftData keeps it outside the store's records where
    /// the shape says to, the way real ink is kept.
    private static let ink = Data((0..<300_000).map { UInt8($0 % 251) })
    private static let content = "# Pointers\n```cpp\nint *p;\n```\n"

    /// Writes a store with two notes the way a build before versions did,
    /// and closes it. `make` builds a note: title, content, ink, created.
    private func writeUnversionedStore<P: PersistentModel>(
        _ type: P.Type,
        make: (String, String, Data, Date) -> P,
        adjust: (P) -> Void = { _ in }
    ) throws {
        let schema = Schema([P.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let context = ModelContext(container)

        let drawn = make("Lecture 1", Self.content, Self.ink, Date(timeIntervalSince1970: 1_000))
        adjust(drawn)
        context.insert(drawn)
        context.insert(make("Plain", "", Data(), Date(timeIntervalSince1970: 3_000)))
        try context.save()
    }

    private func writeUnversionedStore(_ shape: EarlierShape) throws {
        switch shape {
        case .firstPage:
            try writeUnversionedStore(NoteSchemaV1.Page.self) {
                NoteSchemaV1.Page(title: $0, content: $1, drawingData: $2, createdAt: $3)
            }
        case .runDestination:
            try writeUnversionedStore(NoteSchemaV2.Page.self) {
                NoteSchemaV2.Page(title: $0, content: $1, drawingData: $2, createdAt: $3)
            }
        case .pageOrientation:
            try writeUnversionedStore(NoteSchemaV3.Page.self) {
                NoteSchemaV3.Page(title: $0, content: $1, drawingData: $2, createdAt: $3)
            }
        case .externalInk:
            try writeUnversionedStore(NoteSchemaV4.Page.self) {
                NoteSchemaV4.Page(title: $0, content: $1, drawingData: $2, createdAt: $3)
            }
        }
    }

    private func openedNotes(_ storage: Storage) throws -> [Page] {
        let container = try #require(storage.container)
        return try ModelContext(container).fetch(
            FetchDescriptor<Page>(sortBy: [SortDescriptor(\.createdAt)])
        )
    }

    @Test("A store from any earlier build opens with its notes and ink", arguments: EarlierShape.allCases)
    func earlierStoreMigrates(_ shape: EarlierShape) throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeUnversionedStore(shape)

        let storage = Storage.open(at: storeURL)

        #expect(storage.reason == nil)
        #expect(storage.isEphemeral == false)

        let notes = try openedNotes(storage)
        #expect(notes.map(\.title) == ["Lecture 1", "Plain"])

        let drawn = try #require(notes.first)
        #expect(drawn.content == Self.content)
        #expect(drawn.drawingData == Self.ink)
        #expect(drawn.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(drawn.modifiedAt == Date(timeIntervalSince1970: 1_000))

        // What later versions add starts empty.
        #expect(notes.allSatisfy { $0.folder == nil && !$0.isPinned && !$0.isTextLocked })
        #expect(notes[1].drawingData.isEmpty)
        #expect(notes[1].orientation == .portrait)
    }

    @Test("The settings a store from just before versions holds come across")
    func settingsSurvive() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeUnversionedStore(NoteSchemaV4.Page.self) {
            NoteSchemaV4.Page(title: $0, content: $1, drawingData: $2, createdAt: $3)
        } adjust: { drawn in
            drawn.runDestination = "godbolt"
            drawn.pageOrientation = "landscape"
            drawn.modifiedAt = Date(timeIntervalSince1970: 2_000)
        }

        let notes = try openedNotes(Storage.open(at: storeURL))

        let drawn = try #require(notes.first)
        #expect(drawn.runDestination == "godbolt")
        #expect(drawn.orientation == .landscape)
        #expect(drawn.modifiedAt == Date(timeIntervalSince1970: 2_000))
    }

    /// Writes a store the way a build from 3 October on did, with version 5:
    /// one note filed, pinned and drawn on in a pinned folder, one plain.
    private func writeVersionFiveStore() throws {
        let schema = Schema(versionedSchema: NoteSchemaV5.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let context = ModelContext(container)

        let cs133 = NoteSchemaV5.Folder(name: "CS133", createdAt: Date(timeIntervalSince1970: 500))
        cs133.isPinned = true
        cs133.runDestination = "godbolt"
        context.insert(cs133)

        let drawn = NoteSchemaV5.Page(
            title: "Lecture 1", content: Self.content, drawingData: Self.ink,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        drawn.pageOrientation = "landscape"
        drawn.modifiedAt = Date(timeIntervalSince1970: 2_000)
        drawn.isPinned = true
        context.insert(drawn)
        drawn.folder = cs133

        context.insert(NoteSchemaV5.Page(title: "Plain", createdAt: Date(timeIntervalSince1970: 3_000)))
        try context.save()
    }

    @Test("A store with folders opens with its notes, folders, pins and ink, and nothing locked")
    func versionFiveStoreMigrates() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeVersionFiveStore()

        let storage = Storage.open(at: storeURL)

        #expect(storage.reason == nil)
        #expect(storage.isEphemeral == false)

        let notes = try openedNotes(storage)
        #expect(notes.map(\.title) == ["Lecture 1", "Plain"])

        let drawn = try #require(notes.first)
        #expect(drawn.content == Self.content)
        #expect(drawn.drawingData == Self.ink)
        #expect(drawn.orientation == .landscape)
        #expect(drawn.modifiedAt == Date(timeIntervalSince1970: 2_000))
        #expect(drawn.isPinned)

        let folder = try #require(drawn.folder)
        #expect(folder.name == "CS133")
        #expect(folder.isPinned)
        #expect(folder.runDestination == "godbolt")
        #expect(folder.pages?.map(\.title) == ["Lecture 1"])

        #expect(notes[1].folder == nil)
        #expect(notes.allSatisfy { !$0.isTextLocked })
    }

    @Test("A note's text lock is still on after a relaunch")
    func textLockSurvivesRelaunch() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeVersionFiveStore()

        do {
            let storage = Storage.open(at: storeURL)
            let container = try #require(storage.container)
            let context = ModelContext(container)
            let notes = try context.fetch(FetchDescriptor<Page>(sortBy: [SortDescriptor(\.createdAt)]))
            notes[0].isTextLocked = true
            try context.save()
        }

        let relaunched = try openedNotes(Storage.open(at: storeURL))
        #expect(relaunched[0].isTextLocked)
        #expect(!relaunched[1].isTextLocked)
        #expect(relaunched[0].folder?.name == "CS133")
    }

    @Test("A migrated store keeps folders across a relaunch")
    func foldersSurviveRelaunch() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeUnversionedStore(.externalInk)

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
