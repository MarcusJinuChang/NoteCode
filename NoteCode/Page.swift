//
//  Page.swift
//  NoteCode
//

import Foundation
import SwiftData

extension NoteSchemaV1 {

    @Model
    final class Page {
        var title: String = "Untitled"
        var content: String = ""

        /// The note's ink as `PaperMarkup` bytes, in print layout's coordinates;
        /// empty for a note never drawn on. Read and written through
        /// `DrawingCodec` and `DrawingSaveScheduler`.
        ///
        /// Kept outside the store's own records: 1,000 strokes come to 1.1MB, and
        /// the note list would otherwise load each note's ink along with its
        /// title.
        @Attribute(.externalStorage) var drawingData: Data = Data()
        var createdAt: Date = Date.now
        var modifiedAt: Date = Date.now

        /// Which online compiler this page's run buttons open — a
        /// `CodeDestination.id`, or `nil` to follow its folder, and then the
        /// app-wide default.
        ///
        /// Optional so that existing pages migrate without a mapping, and because
        /// "not set" is a real state: a page that never chooses should follow the
        /// default as it changes rather than freeze whatever it was on the day the
        /// page was written. See `runDestinationLevels(appDefault:)`.
        var runDestination: String?

        /// Which way up this note's pages are — a `PageOrientation` raw value, or
        /// `nil` for a note that has never chosen, which is portrait.
        ///
        /// Stored as a string, like `runDestination`, so existing notes migrate
        /// without a mapping. Unlike that setting, a note keeps whatever it is
        /// given rather than following a default: orientation sets where lines
        /// wrap, and a default that changed would re-wrap every note that had
        /// never chosen.
        var pageOrientation: String?

        /// The folder this note is filed in, or `nil` for a note at the top of
        /// the list. A note is in one folder at most: grouping by class wants
        /// nothing more, and a note in several folders would make "move" and
        /// deleting a folder with its notes ambiguous. The other side, and the
        /// delete rule, are on `Folder.pages`.
        var folder: Folder?

        /// Whether the note is pinned to the top of the list.
        var isPinned: Bool = false

        /// Whether the note's text is locked: it can be read, selected and
        /// copied, but not typed into, and tapping it brings up no keyboard.
        /// For reading old notes without changing them by accident. Ink is
        /// left alone, so a locked note can still be drawn on.
        ///
        /// Part of the note, not the device, so it stays locked until it's
        /// unlocked. Like pinning, locking isn't an edit and keeps the date.
        var isTextLocked: Bool = false

        /// When the note was moved to Recently Deleted, or `nil` for a note
        /// that is where the reader left it. A note with a date is out of every
        /// list, search and count (`isLive`) and is purged for good 30 days
        /// after it (`Page.retention`).
        var deletedAt: Date?

        /// The body text's size in points, or `nil` for the default 17. It sets
        /// where lines break; the text options row changes it, and asks first
        /// when the note has ink.
        var textSize: Int?

        /// The points each prose line is made taller than the font makes it,
        /// or `nil` for none (`NoteTypography.lineSpacings`). Line height only.
        /// Like the text size it moves lines under the ink, so the text row
        /// asks first when the note has ink, and it isn't an edit.
        var lineSpacing: Int?

        /// The size and spacing the note is laid out in.
        var typography: NoteTypography { NoteTypography(bodySize: textSize, lineSpacing: lineSpacing) }

        /// The fewest pages the note has, whatever it holds: what Add Page raises,
        /// and what seamless raises when ink reaches the last page, so there is
        /// always a blank page to draw on below. Only ever grows. The note has
        /// the more of this and the pages its text and ink need
        /// (`PageLayout.pageCount`). Like the text size it isn't an edit and
        /// leaves `modifiedAt` alone.
        var minimumPageCount: Int = 1

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

    /// Where this note's code blocks could run, most specific first, for
    /// `RunDestinationPreference.resolve`: the note's own choice, its
    /// folder's, the folders above that in turn, then the app-wide default.
    func runDestinationLevels(appDefault: String) -> [String?] {
        let folders = folder.map { [$0] + $0.ancestors } ?? []
        return [runDestination] + folders.map(\.runDestination) + [appDefault]
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
        let copy = Page(title: "\(title) copy", content: content, drawingData: drawingData)
        copy.pageOrientation = pageOrientation
        copy.textSize = textSize
        copy.lineSpacing = lineSpacing
        copy.minimumPageCount = minimumPageCount
        copy.runDestination = runDestination
        context.insert(copy)
        // After the insert, like `Page.create`: relationships are set on a
        // note the context already knows.
        copy.folder = folder
        return copy
    }
}
