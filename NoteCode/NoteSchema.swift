//
//  NoteSchema.swift
//  NoteCode
//
//  The store's model, version by version, and how a store moves between them.
//

import Foundation
import SwiftData

/// The model the app uses now. Everything outside this file says `Page` and
/// `Folder` and never names a version.
typealias Page = NoteSchemaV7.Page
typealias Folder = NoteSchemaV7.Folder

/// The store's model as it stands, for every container the app opens.
enum NoteSchema {
    static var current: Schema { Schema(versionedSchema: NoteSchemaV7.self) }
}

/// How a store written by an earlier version reaches the current one.
///
/// Until 3 October 2026 the model had no versions at all, and SwiftData
/// migrated silently, which was fine while the only notes were the
/// developer's. Once the app ships, every model change has to carry other
/// people's notes across, and a version history is what makes that testable
/// (`SchemaMigrationTests`). So: never edit a version that has been released.
/// A change to the model is a new version here, a frozen copy of the old one
/// stays, and a stage joins the plan.
///
/// A store is matched to a version by the shape of its entities, and one it
/// can't match doesn't open at all. Versions 1 to 4 are every shape a build
/// wrote before versions existed, recovered from the history of Page.swift,
/// so a store last opened by any of those builds still opens. With only the
/// last of them, stores from before 23 September failed (measured on 3
/// October, on copies of the simulators' stores).
///
/// A store that fails to migrate isn't lost. `Storage` falls back to an
/// in-memory store and says so, and the file on disk is left as it was.
nonisolated enum NoteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            NoteSchemaV1.self, NoteSchemaV2.self, NoteSchemaV3.self, NoteSchemaV4.self,
            NoteSchemaV5.self, NoteSchemaV6.self, NoteSchemaV7.self,
        ]
    }

    static var stages: [MigrationStage] {
        // Only additions, all optional or with defaults, and one attribute
        // moving to external storage: SwiftData carries the notes across
        // unchanged at every step. Version 7 adds a rule on top of its columns,
        // so it's the one custom stage (`migrateToVersionSeven`).
        [
            .lightweight(fromVersion: NoteSchemaV1.self, toVersion: NoteSchemaV2.self),
            .lightweight(fromVersion: NoteSchemaV2.self, toVersion: NoteSchemaV3.self),
            .lightweight(fromVersion: NoteSchemaV3.self, toVersion: NoteSchemaV4.self),
            .lightweight(fromVersion: NoteSchemaV4.self, toVersion: NoteSchemaV5.self),
            .lightweight(fromVersion: NoteSchemaV5.self, toVersion: NoteSchemaV6.self),
            migrateToVersionSeven,
        ]
    }

    /// Version 6 to 7: the new columns arrive empty, then every note without
    /// ink is marked `rendered` (`Page.markdownLayout`).
    ///
    /// This can't be a lightweight stage, which can only give a column one
    /// value for every row. It runs once, inside the migration, so a note is
    /// never seen between the two halves, and it writes nothing but
    /// `markdownLayout`: `modifiedAt` stays what the reader last did, or the
    /// list would reorder itself the first time the new build opened.
    ///
    /// The ink check reads each note's `drawingData`, which lives outside the
    /// store's records, so this loads every note's ink once. That is the cost
    /// of asking "is there any" of a column the store can't test.
    static let migrateToVersionSeven = MigrationStage.custom(
        fromVersion: NoteSchemaV6.self,
        toVersion: NoteSchemaV7.self,
        willMigrate: nil,
        didMigrate: { context in
            for page in try context.fetch(FetchDescriptor<NoteSchemaV7.Page>()) where page.drawingData.isEmpty {
                page.markdownLayout = NoteSchemaV7.Page.renderedMarkdown
            }
            try context.save()
        }
    )
}

// MARK: - Version 7: Recently Deleted, paper, rendered Markdown, text size, folder faces (12 October 2026)

/// v3's only model change: `Page.deletedAt` (Recently Deleted), `paperStyle`,
/// `markdownLayout` and `textSize`, and a colour and a symbol for a folder.
/// Everything optional, so a note that never chose reads as the defaults, and
/// nothing unique, for CloudKit.
///
/// The models themselves are in Page.swift and Folder.swift.
nonisolated enum NoteSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Page.self, Folder.self]
    }
}

// MARK: - Version 6: text lock (4 October 2026), frozen

/// A lock on a note's text, so it can be read without being changed. The shape
/// of every store written between 4 October and the first v3 build.
///
/// A copy of the models as they were, like versions 1 to 5: same names, types,
/// defaults, external storage and relationship. Inside this enum, `Page` and
/// `Folder` are these copies, not the current models.
nonisolated enum NoteSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Page.self, Folder.self]
    }

    @Model
    final class Page {
        var title: String = "Untitled"
        var content: String = ""
        @Attribute(.externalStorage) var drawingData: Data = Data()
        var createdAt: Date = Date.now
        var modifiedAt: Date = Date.now
        var runDestination: String?
        var pageOrientation: String?
        var folder: Folder?
        var isPinned: Bool = false
        var isTextLocked: Bool = false

        init(title: String = "Untitled", content: String = "", drawingData: Data = Data(), createdAt: Date = .now) {
            self.title = title
            self.content = content
            self.drawingData = drawingData
            self.createdAt = createdAt
            self.modifiedAt = createdAt
            self.runDestination = nil
            self.pageOrientation = nil
        }
    }

    @Model
    final class Folder {
        var name: String = ""
        var createdAt: Date = Date.now
        var isPinned: Bool = false
        var runDestination: String?

        @Relationship(deleteRule: .nullify, inverse: \Page.folder)
        var pages: [Page]? = []

        init(name: String, createdAt: Date = .now) {
            self.name = name
            self.createdAt = createdAt
        }
    }
}

// MARK: - Version 5: folders (3 October 2026), frozen

/// Folders, and a pin on notes and folders. The first version written as a
/// version, and in every store opened by a build from 3 October on.
///
/// Shaped for iCloud sync, which is deferred but will need it: CloudKit wants
/// every relationship optional, every attribute optional or with a default,
/// and nothing unique. Meeting that now saves a second migration then.
///
/// A copy of the models as they were, like versions 1 to 4 below: same
/// names, types, defaults, external storage and relationship. Inside this
/// enum, `Page` and `Folder` are these copies, not the current models.
nonisolated enum NoteSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Page.self, Folder.self]
    }

    @Model
    final class Page {
        var title: String = "Untitled"
        var content: String = ""
        @Attribute(.externalStorage) var drawingData: Data = Data()
        var createdAt: Date = Date.now
        var modifiedAt: Date = Date.now
        var runDestination: String?
        var pageOrientation: String?
        var folder: Folder?
        var isPinned: Bool = false

        init(title: String = "Untitled", content: String = "", drawingData: Data = Data(), createdAt: Date = .now) {
            self.title = title
            self.content = content
            self.drawingData = drawingData
            self.createdAt = createdAt
            self.modifiedAt = createdAt
            self.runDestination = nil
            self.pageOrientation = nil
        }
    }

    @Model
    final class Folder {
        var name: String = ""
        var createdAt: Date = Date.now
        var isPinned: Bool = false
        var runDestination: String?

        @Relationship(deleteRule: .nullify, inverse: \Page.folder)
        var pages: [Page]? = []

        init(name: String, createdAt: Date = .now) {
            self.name = name
            self.createdAt = createdAt
        }
    }
}

// MARK: - Versions 1 to 4: before versions, frozen

// Each is a copy of `Page` as a build stored it, and must stay exactly that:
// same names, same types, same optionality, same external storage. They're
// never used to make notes, only to recognise old stores.

/// Ink kept outside the store's records (23 September 2026, "Save ink with
/// the note"). The shape of every store from then until versions.
nonisolated enum NoteSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Page.self]
    }

    @Model
    final class Page {
        var title: String
        var content: String
        @Attribute(.externalStorage) var drawingData: Data
        var createdAt: Date
        var modifiedAt: Date
        var runDestination: String?
        var pageOrientation: String?

        init(title: String = "Untitled", content: String = "", drawingData: Data = Data(), createdAt: Date = .now) {
            self.title = title
            self.content = content
            self.drawingData = drawingData
            self.createdAt = createdAt
            self.modifiedAt = createdAt
            self.runDestination = nil
            self.pageOrientation = nil
        }
    }
}

/// A note's page orientation (13 September 2026, "Paginate notes, add pinch
/// zoom and a view menu").
nonisolated enum NoteSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Page.self]
    }

    @Model
    final class Page {
        var title: String
        var content: String
        var drawingData: Data
        var createdAt: Date
        var modifiedAt: Date
        var runDestination: String?
        var pageOrientation: String?

        init(title: String = "Untitled", content: String = "", drawingData: Data = Data(), createdAt: Date = .now) {
            self.title = title
            self.content = content
            self.drawingData = drawingData
            self.createdAt = createdAt
            self.modifiedAt = createdAt
            self.runDestination = nil
            self.pageOrientation = nil
        }
    }
}

/// A note's run destination (11 September 2026, "Let a note choose where its
/// code runs").
nonisolated enum NoteSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Page.self]
    }

    @Model
    final class Page {
        var title: String
        var content: String
        var drawingData: Data
        var createdAt: Date
        var modifiedAt: Date
        var runDestination: String?

        init(title: String = "Untitled", content: String = "", drawingData: Data = Data(), createdAt: Date = .now) {
            self.title = title
            self.content = content
            self.drawingData = drawingData
            self.createdAt = createdAt
            self.modifiedAt = createdAt
            self.runDestination = nil
        }
    }
}

/// The first `Page` (15 August 2026, "Replace SwiftData template with Page
/// model scaffold").
nonisolated enum NoteSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Page.self]
    }

    @Model
    final class Page {
        var title: String
        var content: String
        var drawingData: Data
        var createdAt: Date
        var modifiedAt: Date

        init(title: String = "Untitled", content: String = "", drawingData: Data = Data(), createdAt: Date = .now) {
            self.title = title
            self.content = content
            self.drawingData = drawingData
            self.createdAt = createdAt
            self.modifiedAt = createdAt
        }
    }
}
