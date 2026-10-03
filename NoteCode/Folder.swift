//
//  Folder.swift
//  NoteCode
//

import Foundation
import SwiftData

extension NoteSchemaV2 {

    /// A group of notes in the list, such as one class's.
    ///
    /// Folders don't nest. A note is in one folder or none (`Page.folder`),
    /// so the list is the notes at its top plus one level of folders.
    @Model
    final class Folder {
        var name: String = ""
        var createdAt: Date = Date.now

        /// Whether the folder is pinned to the top of the list.
        var isPinned: Bool = false

        /// Where the code blocks of this folder's notes run when a note
        /// hasn't chosen for itself — a `CodeDestination.id`, or `nil` to
        /// follow the app-wide default. Sits between the two in
        /// `Page.runDestinationLevels(appDefault:)`.
        var runDestination: String?

        /// The notes filed here, in no particular order.
        ///
        /// Deleting a folder leaves its notes, at the top of the list, unless
        /// they're deleted with it on purpose (`Folder.delete`). Optional
        /// because CloudKit requires it of every relationship.
        @Relationship(deleteRule: .nullify, inverse: \Page.folder)
        var pages: [Page]? = []

        init(name: String, createdAt: Date = .now) {
            self.name = name
            self.createdAt = createdAt
        }
    }
}

extension Folder {

    /// What happens to a folder's notes when it's deleted.
    enum Deletion {
        /// The notes move to the top of the list.
        case keepingNotes
        /// The notes are deleted too.
        case withNotes
    }

    /// The name to give a folder, from what was typed: trimmed, and never
    /// blank, since a folder with no name is a row with nothing to tap.
    static func name(fromTyped typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Folder" : trimmed
    }

    /// Deletes a folder, and its notes too if asked, and saves at once — for
    /// the reason `Page.delete(_:from:)` gives.
    static func delete(_ folder: Folder, _ deletion: Deletion, from context: ModelContext) throws {
        if deletion == .withNotes {
            for page in folder.pages ?? [] {
                context.delete(page)
            }
        }
        context.delete(folder)
        try context.save()
    }
}

/// The note list's rows, worked out from every note and folder.
///
/// Pure, so the list's order is tested without SwiftUI. Notes keep the order
/// they're given in, both inside a folder and at the top level; folders are
/// in name order, the way Files and Notes sort them, with numbers compared as
/// numbers so "CS 9" comes before "CS 133".
struct NoteListSections {
    struct FolderSection: Identifiable {
        let folder: Folder
        let notes: [Page]
        var id: PersistentIdentifier { folder.persistentModelID }
    }

    let folders: [FolderSection]

    /// Notes in no folder.
    let unfiled: [Page]

    init(pages: [Page], folders: [Folder]) {
        var notesByFolder: [PersistentIdentifier: [Page]] = [:]
        var unfiled: [Page] = []
        for page in pages {
            if let folder = page.folder {
                notesByFolder[folder.persistentModelID, default: []].append(page)
            } else {
                unfiled.append(page)
            }
        }

        self.folders = folders
            .sorted {
                switch $0.name.localizedStandardCompare($1.name) {
                case .orderedAscending:  true
                case .orderedDescending: false
                case .orderedSame:       $0.createdAt < $1.createdAt
                }
            }
            .map { FolderSection(folder: $0, notes: notesByFolder[$0.persistentModelID] ?? []) }
        self.unfiled = unfiled
    }
}
