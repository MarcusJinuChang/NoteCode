//
//  ModelFreezeTests.swift
//  NoteCodeTests
//

import CoreData
import Foundation
import SwiftData
import Testing
@testable import NoteCode

/// Version 1 is the model as it ships, and a shipped version never changes.
///
/// SwiftData matches a store to a version by the shape of its entities, as
/// Core Data hashes it. These tests pin version 1's hashes, so a change to
/// `Page` or `Folder` that would leave released stores unopenable fails here
/// rather than on someone's iPad, where `Storage` would fall back to memory and
/// the notes would look gone. See NoteSchema.swift for what to do instead.
@Suite("Freezing the model")
@MainActor
struct ModelFreezeTests {

    /// Version 1's entity hashes, as Core Data computes them, base64. Before
    /// the App Store release these may still be updated with a model change;
    /// after it, a mismatch means a new version (NoteSchema.swift).
    static let versionOneHashes: [String: String] = [
        "Folder": "LHK0l8jTaJCqqayMNtUNEU0jBeLaqXq1jGVdCOzU45Q=",
        "Page": "0Pcr2hCwvm4jqE5XvQ1i6+kVMHYnF4bTFSKY3A27gyU=",
    ]

    private static func hashes(of schema: Schema) throws -> [String: String] {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: schema))
        return model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
    }

    @Test("Version 1's shape is what it was frozen as")
    func versionOneIsFrozen() throws {
        let hashes = try Self.hashes(of: Schema(versionedSchema: NoteSchemaV1.self))
        #expect(hashes == Self.versionOneHashes)
    }

    @Test("The app opens stores with the plan, at its last version")
    func planIsCurrent() throws {
        let last = try #require(NoteMigrationPlan.schemas.last)
        #expect(ObjectIdentifier(last) == ObjectIdentifier(NoteSchemaV1.self))
        #expect(NoteMigrationPlan.stages.count == NoteMigrationPlan.schemas.count - 1)
        #expect(try Self.hashes(of: NoteSchema.current) == Self.hashes(of: Schema(versionedSchema: last)))

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ModelFreezeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = try #require(Storage.open(at: directory.appending(path: "notes.store")).container)
        let plan = try #require(container.migrationPlan)
        #expect(ObjectIdentifier(plan) == ObjectIdentifier(NoteMigrationPlan.self))
    }

    /// The TestFlight builds from 17 Oct opened their store with no versions:
    /// a plain schema of the two classes. Their testers' notes have to open
    /// as version 1 with nothing lost.
    @Test("A store written before versions started opens as version 1")
    func storeFromBeforeVersionsOpens() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ModelFreezeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "notes.store")

        // Big enough that SwiftData keeps it outside the store's records, as
        // real ink is kept.
        let ink = Data((0..<300_000).map { UInt8($0 % 251) })
        let created = Date(timeIntervalSince1970: 1_000)
        let deleted = Date(timeIntervalSince1970: 5_000)

        do {
            let unversioned = Schema([Page.self, Folder.self])
            let container = try ModelContainer(
                for: unversioned,
                configurations: [ModelConfiguration(schema: unversioned, url: url)]
            )
            let context = ModelContext(container)
            let course = Folder(name: "CS133")
            let labs = Folder(name: "Labs")
            context.insert(course)
            context.insert(labs)
            labs.parent = course
            labs.sortIndex = 0
            labs.colorName = "blue"

            let lecture = Page(title: "Lecture 1", content: "# Pointers\n```cpp\nint *p;\n```\n", drawingData: ink, createdAt: created)
            context.insert(lecture)
            lecture.folder = labs
            lecture.pageOrientation = "landscape"
            lecture.textSize = 19
            lecture.minimumPageCount = 3
            lecture.isPinned = true

            let gone = Page(title: "Old", createdAt: created)
            context.insert(gone)
            gone.deletedAt = deleted
            try context.save()
        }

        let storage = Storage.open(at: url)
        #expect(storage.reason == nil)
        #expect(storage.isEphemeral == false)

        let context = ModelContext(try #require(storage.container))
        let notes = try context.fetch(FetchDescriptor<Page>(sortBy: [SortDescriptor(\.title)]))
        #expect(notes.map(\.title) == ["Lecture 1", "Old"])

        let lecture = try #require(notes.first)
        #expect(lecture.drawingData == ink)
        #expect(lecture.content == "# Pointers\n```cpp\nint *p;\n```\n")
        #expect(lecture.createdAt == created && lecture.modifiedAt == created)
        #expect(lecture.orientation == .landscape)
        #expect(lecture.textSize == 19 && lecture.minimumPageCount == 3 && lecture.isPinned)
        #expect(lecture.folder?.name == "Labs")
        #expect(lecture.folder?.parent?.name == "CS133")
        #expect(lecture.folder?.colorName == "blue" && lecture.folder?.sortIndex == 0)
        #expect(notes[1].deletedAt == deleted)
    }
}
