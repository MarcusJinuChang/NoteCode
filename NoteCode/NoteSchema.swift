//
//  NoteSchema.swift
//  NoteCode
//
//  The store's model, version by version, and how a store moves between them.
//

import Foundation
import SwiftData

/// The model the app uses now. Everything outside the model files says `Page`
/// and `Folder` and never names a version.
typealias Page = NoteSchemaV1.Page
typealias Folder = NoteSchemaV1.Folder

/// The store's model as it stands, for every container the app opens.
enum NoteSchema {
    static var current: Schema { Schema(versionedSchema: NoteSchemaV1.self) }
}

/// How a store written by an earlier version reaches the current one.
///
/// **Versioning starts with what ships** (step 13 of docs/ROADMAP.md). Until
/// the App Store release the model was edited in place, with no migration
/// (decided 15 Oct 2026); the versions 1 to 7 that stood here before then are
/// in the history of this file, and none of their stores are kept.
///
/// From the release on, **never edit a version that has shipped.** A change
/// to the model is a new version: the classes as they were are copied into
/// `NoteSchemaV1` as a frozen copy (same names, types, defaults, external
/// storage and relationships; the history of this file shows the shape), the
/// live classes move to `extension NoteSchemaV2` in Page.swift and
/// Folder.swift, the typealiases above follow them, and a stage joins
/// `stages`. A test writes a store with the frozen copy and opens it through
/// `Storage`, never a container built some other way.
///
/// A store is matched to a version by the shape of its entities, and one it
/// can't match doesn't open at all, so `ModelFreezeTests` pins version 1's
/// shape as SwiftData hashes it. Before the release, a model change may still
/// edit version 1 in place, and the pinned hashes with it; TestFlight testers
/// then reinstall. After it, a changed hash means a new version.
///
/// A store that fails to migrate isn't lost. `Storage` falls back to an
/// in-memory store and says so, and the file on disk is left as it was.
///
/// Shaped for CloudKit, so iCloud sync later needs no migration of its own:
/// every relationship optional, every attribute optional or with a default,
/// nothing `.unique`.
nonisolated enum NoteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NoteSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

// MARK: - Version 1: the model as it ships (November 2026)

/// Notes and folders as the first App Store build stores them. A store
/// written by a build from before versions started (the TestFlight builds
/// from 17 Oct) has the same shape, so it opens as this version with nothing
/// to migrate.
///
/// The models themselves are in Page.swift and Folder.swift.
nonisolated enum NoteSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Page.self, Folder.self]
    }
}
