//
//  NoteSchema.swift
//  NoteCode
//
//  The store's model.
//

import Foundation
import SwiftData

/// The model the app uses, for every container it opens.
///
/// **Unversioned until the release** (decided 15 Oct 2026). Nothing important
/// is stored in the app yet, so a model change is made in place, with no
/// migration: a store that won't open is deleted with the app. Step 13 of
/// docs/ROADMAP.md freezes what ships as version 1, and from then on a model
/// change is a new `VersionedSchema` with its own copies of the classes and
/// a stage in a plan, tested by writing a store in the old shape and opening
/// it through `Storage`. The versions 1 to 7 that stood here before 15 Oct are
/// in the history of this file.
///
/// A store that can't be opened isn't lost. `Storage` falls back to an
/// in-memory store and says so, and the file on disk is left as it was.
///
/// Shaped for CloudKit, so iCloud sync later needs no migration of its own:
/// every relationship optional, every attribute optional or with a default,
/// nothing `.unique`.
enum NoteSchema {
    static var current: Schema { Schema([Page.self, Folder.self]) }
}
