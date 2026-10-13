//
//  NoteMemory.swift
//  NoteCode
//
//  What this device remembers about notes: the one opened last, and the page
//  each was left at. Pure, over a `UserDefaults`, so the rules are tested
//  without a view.
//

import Foundation
import SwiftData

/// The note opened last, and the page each note was read at, per device.
///
/// **Per device, not in the note.** Where someone was reading is a fact about
/// that iPad, like the view mode and the hotbar's dock: it isn't an edit, so it
/// must not move `modifiedAt` (opening a note would reorder the list), and it
/// needs no model change. Keyed by the note's persistent ID, which a note keeps
/// for as long as it lives.
///
/// A new note's ID is *temporary* until the context first saves it, and changes
/// when it does; a key made from one would never match again. `key(for:)`
/// refuses such an ID, and `ID.settled(for:)` saves first.
nonisolated struct NoteMemory {

    /// The note opened last, as an encoded `PersistentIdentifier`.
    static let lastOpenedKey = "lastOpenedNote"

    /// Every note's place: encoded ID -> `[page, of]`, in one dictionary
    /// rather than one defaults key per note.
    static let placesKey = "notePlaces"

    /// Where a note was left: a page counted from 0, out of how many it had.
    ///
    /// "Out of" is kept because only a laid-out note knows its page count, and
    /// Home shows "page 3 of 5" for a note that isn't open.
    struct Place: Equatable, Sendable {
        var page: Int
        var of: Int

        /// Counted from 1, as pages are on screen.
        var number: Int { page + 1 }
    }

    var defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Keys

    /// The ID as a string a defaults dictionary can hold, or `nil` for a
    /// temporary one.
    ///
    /// **Sorted keys.** `JSONEncoder` writes an object's keys in no fixed
    /// order, so the same ID gave different strings on different calls: a
    /// place stored under one was never found under the next, and the cache
    /// name of a thumbnail changed between asking for it and storing it
    /// (found by `NoteMemoryTests`; Home's pictures stayed blank).
    static func key(for id: PersistentIdentifier) -> String? {
        guard !id.isTemporary else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(id) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: The note opened last

    /// The key of the note opened last, to compare with `key(for:)`.
    ///
    /// Notes are found by key, never by decoding it back into an ID: a decoded
    /// ID didn't always behave as the original in a `Set`.
    func lastOpenedKey() -> String? {
        defaults.string(forKey: Self.lastOpenedKey)
    }

    func setLastOpened(_ id: PersistentIdentifier) {
        guard let key = Self.key(for: id) else { return }
        defaults.set(key, forKey: Self.lastOpenedKey)
    }

    // MARK: Places

    private var places: [String: [Int]] {
        let stored = defaults.dictionary(forKey: Self.placesKey) ?? [:]
        return stored.compactMapValues { value in
            (value as? [Any])?.compactMap { $0 as? Int }
        }
    }

    func place(of id: PersistentIdentifier) -> Place? {
        guard let key = Self.key(for: id),
              let pair = places[key], pair.count == 2,
              pair[0] >= 0, pair[1] >= 1
        else { return nil }
        return Place(page: pair[0], of: pair[1])
    }

    func setPlace(_ place: Place, of id: PersistentIdentifier) {
        guard let key = Self.key(for: id) else { return }
        var all = places
        all[key] = [max(place.page, 0), max(place.of, 1)]
        defaults.set(all, forKey: Self.placesKey)
    }

    /// Forgets every place whose note is gone, so the dictionary doesn't grow
    /// with each note ever made. Run once a launch, with every note's ID
    /// (deleted ones too: a note in Recently Deleted can come back).
    func prune(keeping ids: Set<PersistentIdentifier>) {
        // By key, not by decoding each stored key back into an ID and asking
        // the set: a decoded ID didn't always compare equal to the one it came
        // from, and every place was forgotten at each launch.
        let live = Set(ids.compactMap(Self.key(for:)))
        let all = places
        let kept = all.filter { live.contains($0.key) }
        if kept.count != all.count {
            defaults.set(kept, forKey: Self.placesKey)
        }
        if let last = defaults.string(forKey: Self.lastOpenedKey), !live.contains(last) {
            defaults.removeObject(forKey: Self.lastOpenedKey)
        }
    }
}

extension NoteMemory {
    /// Notes `page` as the one opened last.
    @MainActor
    func rememberOpened(_ page: Page) {
        if let id = page.settledID {
            setLastOpened(id)
        }
    }
}

extension Page {
    /// The note's ID once it can be remembered: saved first if it was still
    /// temporary, which is the case for a note made moments ago.
    ///
    /// Saves only for that case, and only the context the note is in. The
    /// autosave would have done the same within seconds.
    @MainActor
    var settledID: PersistentIdentifier? {
        if persistentModelID.isTemporary {
            try? modelContext?.save()
        }
        let id = persistentModelID
        return id.isTemporary ? nil : id
    }
}
