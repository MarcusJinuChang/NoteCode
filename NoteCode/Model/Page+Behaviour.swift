//
//  Page+Behaviour.swift
//  NoteCode
//
//  What a note does: titles, deleting and restoring, duplicating. Out of the frozen
//  class (Page.swift), whose hashes ModelFreezeTests holds.
//

import Foundation
import SwiftData

extension Page {
    /// The title to give a note, from what was typed: trimmed, and never
    /// blank, as a folder's name isn't.
    static func title(fromTyped typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var orientation: PageOrientation {
        get { pageOrientation.flatMap(PageOrientation.init(rawValue:)) ?? .default }
        set { pageOrientation = newValue.rawValue }
    }
}

extension Page {
    /// Deletes notes, and saves the deletion straight away.
    ///
    /// The store autosaves on its own schedule, and a deletion the app was
    /// killed before then — by a crash, or Xcode starting the next build —
    /// came back on the next launch. The open note also saves when the app
    /// leaves the screen, but a deleted note is closed first, and the note
    /// list saves nothing on its own.
    static func delete(_ pages: some Sequence<Page>, from context: ModelContext) throws {
        for page in pages {
            context.delete(page)
        }
        try context.save()
    }
}

// MARK: - Recently Deleted

extension Page {
    /// How long a deleted note waits in Recently Deleted: 30 days.
    static let retention: TimeInterval = 30 * 86_400

    /// Whether the note is where the reader left it, and not in Recently
    /// Deleted. **Every view of notes asks this** — the list, search, Home, a
    /// folder's count, "the open note's folder", Export All — so a deleted note
    /// is in none of them. Use `live` on a collection rather than testing
    /// `deletedAt` at the call site.
    var isLive: Bool { deletedAt == nil }

    /// Matches the notes in Recently Deleted, for a `@Query` of just those.
    /// The opposite of `isLive`; `PageDeletionTests` fetches with it.
    static var deletedPredicate: Predicate<Page> {
        #Predicate<Page> { $0.deletedAt != nil }
    }

    /// Whole days left before the note is purged: 30 on the day it was
    /// deleted, then one fewer each day. `nil` for a note not in Recently
    /// Deleted.
    func daysLeft(now: Date = .now) -> Int? {
        guard let deletedAt else { return nil }
        let elapsedDays = Int(max(0, now.timeIntervalSince(deletedAt)) / 86_400)
        return max(0, Int(Self.retention / 86_400) - elapsedDays)
    }

    /// Moves notes to Recently Deleted, and saves at once, for the reason
    /// `Page.delete(_:from:)` gives.
    ///
    /// A note already there keeps its first date, so deleting twice doesn't
    /// restart its 30 days. `modifiedAt` is left alone: deleting isn't an
    /// edit, and a restored note should sort where it was.
    ///
    /// The ink isn't touched. It stays in the note, unread, until the note is
    /// purged with `delete(_:from:)`.
    static func moveToRecentlyDeleted(_ pages: some Sequence<Page>, from context: ModelContext, now: Date = .now) throws {
        for page in pages where page.isLive {
            page.deletedAt = now
        }
        try context.save()
    }

    /// Whether the note went to Recently Deleted along with its folder, and so
    /// is shown under the folder's row there rather than as a row of its own.
    var isDeletedWithFolder: Bool {
        guard let deletedAt, let folder, !folder.isLive else { return false }
        return folder.deletedAt == deletedAt
    }

    /// Brings notes back from Recently Deleted, and saves.
    ///
    /// A note goes back to its folder. If the folder has been deleted since,
    /// the relationship was cleared with it (`Folder.pages` nullifies), so the
    /// note comes back at the top of the list. If the folder is waiting in
    /// Recently Deleted itself, the same: restoring one note doesn't bring its
    /// folder back, and a note must not sit in a folder the reader can't see.
    static func restore(_ pages: some Sequence<Page>, in context: ModelContext) throws {
        for page in pages {
            page.deletedAt = nil
            if let folder = page.folder, !folder.isLive {
                page.folder = nil
            }
        }
        try context.save()
    }

    /// Deletes for good every folder and note that has been in Recently Deleted
    /// for more than 30 days. Run at launch.
    ///
    /// Folders go first, with the notes that went with them, so a note is never
    /// deleted twice. A folder's notes share its date, so they are due with it.
    ///
    /// - Returns: how many notes were purged.
    @discardableResult
    static func purgeExpired(in context: ModelContext, now: Date = .now) throws -> Int {
        let cutoff = now.addingTimeInterval(-retention)
        let expiredFolders = try context.fetch(FetchDescriptor<Folder>(predicate: Folder.deletedPredicate))
            .filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        // Counted once: a folder's notes include those of the folders in it,
        // which are due with it and may be in this list too.
        let withFolders = Set(expiredFolders.flatMap(\.notesDeletedWithIt).map(\.persistentModelID)).count
        try Folder.deleteForGood(expiredFolders, from: context)

        let expired = try context.fetch(FetchDescriptor<Page>(predicate: deletedPredicate))
            .filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        // `delete` reads nothing from the notes: a deleted note's ink can't be
        // read once the deletion is saved (see AGENTS.md).
        if !expired.isEmpty { try delete(expired, from: context) }
        return withFolders + expired.count
    }
}

extension Sequence where Element == Page {
    /// The notes that aren't in Recently Deleted. See `Page.isLive`.
    var live: [Page] { filter(\.isLive) }
}

// MARK: - Duplicate

extension Page {
    /// A copy of the note, inserted into `context`.
    ///
    /// It copies what makes the note the note: its text, ink, page orientation,
    /// text size, folder and run destination. It leaves
    /// out the pin and the text lock, which belong to the original, and has
    /// dates of its own. The title gains " copy".
    ///
    /// The original's modified date doesn't move.
    @discardableResult
    func duplicated(in context: ModelContext) -> Page {
        let copy = Page(title: "\(displayTitle) copy", content: content, drawingData: drawingData)
        copy.pageOrientation = pageOrientation
        copy.textSize = textSize
        copy.lineSpacing = lineSpacing
        copy.minimumPageCount = minimumPageCount
        context.insert(copy)
        // After the insert, like `Page.create`: relationships are set on a
        // note the context already knows.
        copy.folder = folder
        return copy
    }
}
