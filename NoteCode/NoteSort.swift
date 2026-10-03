//
//  NoteSort.swift
//  NoteCode
//
//  The order of notes in the list.
//

import Foundation

/// How the note list orders notes: by which date, or by title, and which
/// way round.
///
/// A preference about this device, like the view mode, not a property of
/// any note, so it lives in `@AppStorage` and changes nothing in the store.
/// Folders aren't sorted by it: they stay in name order, so they're always
/// where the reader left them.
nonisolated struct NoteSort: Equatable, Sendable {

    nonisolated enum Key: String, CaseIterable, Sendable {
        case modified
        case created
        case title

        var title: String {
            switch self {
            case .modified: "Date Modified"
            case .created:  "Date Created"
            case .title:    "Title"
            }
        }

        /// The way round a reader expects when picking this key: newest first
        /// for dates, A to Z for titles.
        var naturallyAscending: Bool {
            self == .title
        }
    }

    var key: Key
    var ascending: Bool

    static let defaultsKey = "noteSort"
    static let `default` = NoteSort(key: .modified, ascending: false)

    /// This sort with another key, the way round that key reads naturally.
    /// Switching from newest-first modified to title gives A to Z, not Z to A.
    func with(key: Key) -> NoteSort {
        NoteSort(key: key, ascending: key.naturallyAscending)
    }

    /// The menu's names for the two ways round, ascending first.
    var orderTitles: (ascending: String, descending: String) {
        switch key {
        case .modified, .created: ("Oldest First", "Newest First")
        case .title:              ("A to Z", "Z to A")
        }
    }

    /// The date a note's row shows: the one the list is sorted by, or when it
    /// was last changed when sorted by title.
    func displayedDate(modified: Date, created: Date) -> Date {
        key == .created ? created : modified
    }

    /// Whether a note with these properties comes before another.
    ///
    /// Ties fall back to title and then creation, so notes made in the same
    /// second, or sharing a title, still keep one order from launch to
    /// launch.
    func areInIncreasingOrder(
        _ a: (title: String, modified: Date, created: Date),
        _ b: (title: String, modified: Date, created: Date)
    ) -> Bool {
        let primary: ComparisonResult = switch key {
        case .modified: compare(a.modified, b.modified)
        case .created:  compare(a.created, b.created)
        case .title:    a.title.localizedStandardCompare(b.title)
        }
        if primary != .orderedSame {
            return ascending ? primary == .orderedAscending : primary == .orderedDescending
        }
        let byTitle = a.title.localizedStandardCompare(b.title)
        if byTitle != .orderedSame {
            return byTitle == .orderedAscending
        }
        return a.created < b.created
    }

    private func compare(_ a: Date, _ b: Date) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}

extension NoteSort: RawRepresentable {
    /// `key;ascending|descending`, for `@AppStorage`.
    nonisolated var rawValue: String {
        "\(key.rawValue);\(ascending ? "ascending" : "descending")"
    }

    /// `nil` for anything that isn't a sort, which leaves `@AppStorage` on
    /// its default rather than on a half-read value.
    nonisolated init?(rawValue: String) {
        let parts = rawValue.split(separator: ";").map(String.init)
        guard parts.count == 2, let key = Key(rawValue: parts[0]) else { return nil }
        switch parts[1] {
        case "ascending":  self.init(key: key, ascending: true)
        case "descending": self.init(key: key, ascending: false)
        default:           return nil
        }
    }
}
