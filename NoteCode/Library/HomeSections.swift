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
            return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
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

    /// "Edited 5 minutes ago", "Edited yesterday", worked out against `now`,
    /// so a view that is handed a new `now` each minute stays true.
    static func edited(_ date: Date, now: Date = .now, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        // A note edited a moment ago is "now", not "0 seconds ago"; a date a
        // little ahead of the clock (iCloud, a skewed clock) reads as now too.
        let seconds = now.timeIntervalSince(date)
        let shown = seconds < 60 ? now : date
        return "Edited " + formatter.localizedString(for: shown, relativeTo: now)
    }

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

/// Whether Home is laid out as on a phone: two-column grids, a small Continue
/// card, buttons stacked (docs/design/iphone-and-the-duo.md).
///
/// A compact width always is. So is a regular one narrower than the iPad
/// layout fits, as beside the list on a portrait 11-inch (about 500pt): there
/// the Continue card broke its title mid-word, folder tiles lost their names
/// and the buttons wrapped.
nonisolated enum HomeLayout {

    /// The narrowest Home the iPad layout fits: the Continue card's
    /// thumbnail, title and Open pill inside the 40pt margins.
    static let regularMinimumWidth: CGFloat = 700

    /// - Parameter width: Home's width, or 0 before it has been measured,
    ///   when the size class decides alone.
    static func isCompact(compactSizeClass: Bool, width: CGFloat) -> Bool {
        compactSizeClass || (width > 0 && width < regularMinimumWidth)
    }

    /// The narrowest a folder tile may be: its 44pt badge, the gaps, and room
    /// for a name like "Data Structures" on two lines. The 4 columns an iPad
    /// layout used gave an iPad mini's landscape Home (beside the list) 170pt
    /// a tile, and names were cut.
    static let folderTileMinimumWidth: CGFloat = 200
    static let folderTileSpacing: CGFloat = 16

    /// How many folder tiles go across `contentWidth` (Home's width less its
    /// margins): at most 4, and 2 at the least, which a phone's 2-column grid
    /// is. Before the width is known (0), the layout's usual count.
    static func folderColumns(contentWidth: CGFloat, isCompact: Bool) -> Int {
        guard contentWidth > 0 else { return isCompact ? 2 : 4 }
        let fit = Int((contentWidth + folderTileSpacing) / (folderTileMinimumWidth + folderTileSpacing))
        return isCompact ? 2 : min(4, max(2, fit))
    }
}
