//
//  Folder.swift
//  NoteCode
//

import Foundation
import SwiftData

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

    /// When the folder was moved to Recently Deleted, or `nil` for a folder
    /// that is where the reader left it. Set only by deleting a folder
    /// **with its notes**, which stamps every note it moves with the same date,
    /// so restoring the folder knows which notes went with it
    /// (`Page.isDeletedWithFolder`). Deleting a folder and keeping its notes
    /// removes it for good: there is nothing in it to bring back.
    var deletedAt: Date?

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

    /// Whether the folder is where the reader left it, and not in Recently
    /// Deleted. **Every view of folders asks this**, as every view of notes
    /// asks `Page.isLive`: the list, Home, Move to Folder, Export All. Use
    /// `live` on a collection rather than testing `deletedAt` at the call site.
    var isLive: Bool { deletedAt == nil }

    /// Matches the folders in Recently Deleted, for a `@Query` of just those.
    static var deletedPredicate: Predicate<Folder> {
        #Predicate<Folder> { $0.deletedAt != nil }
    }

    /// Whole days left before the folder is purged, as `Page.daysLeft`.
    func daysLeft(now: Date = .now) -> Int? {
        guard let deletedAt else { return nil }
        let elapsedDays = Int(max(0, now.timeIntervalSince(deletedAt)) / 86_400)
        return max(0, Int(Page.retention / 86_400) - elapsedDays)
    }

    /// The notes that were moved to Recently Deleted along with this folder:
    /// the ones stamped with its date. A note deleted on its own before is in
    /// the folder too, and isn't one of these.
    var notesDeletedWithIt: [Page] {
        guard let deletedAt else { return [] }
        return (pages ?? []).filter { $0.deletedAt == deletedAt }
    }

    /// Deletes a folder, and saves at once — for the reason
    /// `Page.delete(_:from:)` gives.
    ///
    /// **Keeping its notes**, the folder is gone for good and they move to the
    /// top of the list. **With them**, the folder and the notes the reader could
    /// see move to Recently Deleted together, under one date, and
    /// `restore(_:in:)` brings them back together. A note already in Recently
    /// Deleted keeps its first date and its place.
    static func delete(_ folder: Folder, _ deletion: Deletion, from context: ModelContext, now: Date = .now) throws {
        switch deletion {
        case .keepingNotes:
            context.delete(folder)
        case .withNotes:
            for page in folder.livePages {
                page.deletedAt = now
            }
            // A folder deleted twice keeps its first date.
            if folder.isLive { folder.deletedAt = now }
        }
        try context.save()
    }

    /// Brings folders back from Recently Deleted, each with the notes that went
    /// with it, and saves.
    static func restore(_ folders: some Sequence<Folder>, in context: ModelContext) throws {
        for folder in folders {
            for page in folder.notesDeletedWithIt {
                page.deletedAt = nil
            }
            folder.deletedAt = nil
        }
        try context.save()
    }

    /// Deletes folders in Recently Deleted for good, with the notes that went
    /// with them, and saves. Reads nothing from the notes, as `Page.delete`
    /// doesn't.
    static func deleteForGood(_ folders: some Sequence<Folder>, from context: ModelContext) throws {
        for folder in folders {
            for page in folder.notesDeletedWithIt {
                context.delete(page)
            }
            context.delete(folder)
        }
        try context.save()
    }
}

extension Sequence where Element == Folder {
    /// The folders that aren't in Recently Deleted. See `Folder.isLive`.
    var live: [Folder] { filter(\.isLive) }
}
