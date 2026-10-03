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
typealias Page = NoteSchemaV2.Page
typealias Folder = NoteSchemaV2.Folder

/// The store's model as it stands, for every container the app opens.
enum NoteSchema {
    static var current: Schema { Schema(versionedSchema: NoteSchemaV2.self) }
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
/// A store that fails to migrate isn't lost. `Storage` falls back to an
/// in-memory store and says so, and the file on disk is left as it was.
nonisolated enum NoteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NoteSchemaV1.self, NoteSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        // Only additions, all optional or with defaults: SwiftData moves the
        // notes across unchanged.
        [.lightweight(fromVersion: NoteSchemaV1.self, toVersion: NoteSchemaV2.self)]
    }
}

// MARK: - Version 2: folders

/// Folders, and a pin on notes and folders (3 October 2026).
///
/// Shaped for iCloud sync, which is deferred but will need it: CloudKit wants
/// every relationship optional, every attribute optional or with a default,
/// and nothing unique. Meeting that now saves a second migration then.
///
/// The models themselves are in Page.swift and Folder.swift.
nonisolated enum NoteSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Page.self, Folder.self]
    }
}

// MARK: - Version 1: notes only

/// The model as it was before versions, frozen.
///
/// This is what every store written before 3 October 2026 holds, and a store
/// is matched to its version by the shape of its entities, so this copy must
/// stay exactly as it was: same names, same types, same optionality, same
/// external storage. It's never used to make notes, only to recognise old
/// stores.
nonisolated enum NoteSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

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
