//
//  HomeSections.swift
//  NoteCode
//
//  What Home shows, worked out from every note and folder. Pure, like
//  `NoteListSections`, so what goes where is tested without SwiftUI.
//

import Foundation
import SwiftData

/// Home's sections: Continue, Recent and Folders.
///
/// - **Continue** is the note last opened on this device. If that note is gone
///   (deleted, or its place was never recorded: a fresh install, a note made
///   moments ago), it is the note edited last, so Home isn't left without a
///   way back in.
/// - **Recent** is the next eight notes by date modified, less Continue's:
///   no note appears twice on one screen.
/// - **Folders** are every folder in name order, with the notes the reader
///   sees in each.
///
/// Notes in Recently Deleted are in none of it (`Page.isLive`), so Home can
/// be handed every note.
struct HomeSections {
    struct FolderTile: Identifiable {
        let folder: Folder
        /// Live notes only, pinned ones included.
        let noteCount: Int
        var id: PersistentIdentifier { folder.persistentModelID }
    }

    /// How many notes Recent holds: a row and a bit of the grid's five columns.
    static let recentLimit = 8

    let continuing: Page?
    let recent: [Page]
    let folders: [FolderTile]

    /// True when the reader has no notes at all, which is when Home shows its
    /// empty state. A folder with nothing in it doesn't make a note.
    let hasNoNotes: Bool

    /// - Parameter lastOpened: the key of the note opened last
    ///   (`NoteMemory.lastOpenedKey()`). Matched by key rather than by decoding
    ///   it back into an ID: see `NoteMemory.prune`.
    init(pages: [Page], folders: [Folder], lastOpened: String?) {
        let live = pages.live.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        hasNoNotes = live.isEmpty

        // Newest first, and the one opened last is nearly always near the top,
        // so this encodes a few IDs, not all of them.
        let continuing = lastOpened.flatMap { key in
            live.first { NoteMemory.key(for: $0.persistentModelID) == key }
        } ?? live.first
        self.continuing = continuing
        recent = Array(live.filter { $0 !== continuing }.prefix(Self.recentLimit))

        var counts: [PersistentIdentifier: Int] = [:]
        for page in live {
            if let folder = page.folder {
                counts[folder.persistentModelID, default: 0] += 1
            }
        }
        // Top-level folders only, in the order the reader arranged them; a
        // tile's count includes the folders in it.
        func count(_ folder: Folder) -> Int {
            (counts[folder.persistentModelID] ?? 0) + (folder.subfolders ?? []).live.reduce(0) { $0 + count($1) }
        }
        self.folders = Folder.arranged(folders.live.filter { $0.parent.map { !$0.isLive } ?? true })
            .map { FolderTile(folder: $0, noteCount: count($0)) }
    }
}

/// How Home dates a note: the words a person would use for how long ago it was.
nonisolated enum HomeDate {

    /// "Today", "Yesterday", the weekday for the rest of the last week, then
    /// the date ("21 Sep"), with the year when it isn't this one.
    static func label(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) {
            return "Yesterday"
        }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? .max

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        if (2...6).contains(days) {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("d MMM y")
        }
        return formatter.string(from: date)
    }
}

/// The line of a note Home quotes under its title: the first line of prose,
/// as the page draws it, with the Markdown markers left out.
nonisolated enum HomeExcerpt {

    /// How much of a note is read: a note that opens with a screenful of code
    /// has nothing to quote, and parsing a long note for one line is waste.
    private static let scanned = 4_000

    /// The first line that is neither blank, a heading, a rule, a fence nor
    /// inside a code block, with its markers (and a list's bullet, a quote's
    /// `>`) dropped, cut to a length a card holds. A line with no text left
    /// is passed over. `nil` for a note with no prose.
    static func of(_ content: String, limit: Int = 160) -> String? {
        let source = String(content.prefix(scanned))
        for block in DocumentParser.parse(source) {
            switch block.kind {
            case .code, .heading, .rule, .math: continue
            case .paragraph, .listItem, .blockQuote: break
            }
            // Same projection as the outline's titles: the words between the
            // markers, a link's text without its address.
            let words = block.inlines.filter { !$0.kind.isMarker }.map { String(source[$0.range]) }.joined()
            let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(limit)) }
        }
        return nil
    }
}
