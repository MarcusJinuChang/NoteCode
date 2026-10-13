//
//  Folder.swift
//  NoteCode
//

import Foundation
import SwiftData

extension NoteSchemaV7 {

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

        /// The folder's colour — a `FolderColor` raw value — or `nil`, which
        /// is orange. A name rather than a colour, so the same folder is the
        /// light tint in light and the dark tint in dark.
        var colorName: String?

        /// The folder's symbol, an SF Symbol name from `FolderSymbol.all`, or
        /// `nil`, which is `folder`.
        var symbolName: String?

        /// The notes filed here, in no particular order.
        ///
        /// Deleting a folder leaves its notes, at the top of the list, unless
        /// they're deleted with it on purpose (`Folder.delete`). Notes in
        /// Recently Deleted are in here too; ask `livePages` for the ones the
        /// reader sees. Optional because CloudKit requires it of every
        /// relationship.
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

    /// The notes filed here that the reader can see: not the ones in Recently
    /// Deleted. What a folder's count, its dialog and its tile show.
    var livePages: [Page] { (pages ?? []).live }

    /// Deletes a folder, and saves at once — for the reason
    /// `Page.delete(_:from:)` gives.
    ///
    /// The folder itself is gone for good. Its notes are kept at the top of the
    /// list, or, with `.withNotes`, moved to Recently Deleted, not deleted:
    /// they can be restored, to the top of the list since their folder isn't
    /// there. A note already in Recently Deleted keeps its first date.
    static func delete(_ folder: Folder, _ deletion: Deletion, from context: ModelContext, now: Date = .now) throws {
        if deletion == .withNotes {
            for page in folder.livePages {
                page.deletedAt = now
            }
        }
        context.delete(folder)
        try context.save()
    }
}
