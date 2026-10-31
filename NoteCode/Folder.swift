//
//  Folder.swift
//  NoteCode
//

import Foundation
import SwiftData

extension NoteSchemaV1 {

    /// A group of notes in the list, such as one class's.
    ///
    /// A note is in one folder or none (`Page.folder`). Folders nest (16 Oct):
    /// a folder is in another folder or at the top (`parent`), as many levels
    /// down as the reader likes, and the reader arranges the folders at each
    /// level by hand (`sortIndex`). Where a folder or note may go is
    /// `ListDrop`'s business, and the rule that keeps a folder out of its own
    /// subtree is `canMove(into:)`.
    @Model
    final class Folder {
        var name: String = ""
        var createdAt: Date = Date.now

        /// Whether the folder is pinned to the top of the list.
        var isPinned: Bool = false

        /// Unused since 30 Oct, like `Page.runDestination`: kept so version
        /// 1's hashes stay as they are.
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

        /// The folder this one is in, or `nil` for a folder at the top of the list.
        var parent: Folder?

        /// The folders in this one. Deleting a folder moves its subfolders to
        /// its own parent (`Folder.delete`), so the nullify rule never has to.
        /// Optional because CloudKit requires it of every relationship.
        @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
        var subfolders: [Folder]? = []

        /// Where the folder sits among the folders with the same parent: the
        /// reader's order, set whenever a folder is dragged (`Folder.move`).
        /// `Int.max` is "never arranged", which sorts after every arranged
        /// folder, by name, so a new folder lands at the end of its level.
        var sortIndex: Int = Int.max

        /// The notes filed here, in no particular order.
        ///
        /// Deleting a folder leaves its notes, in its parent (or the top of the list), unless
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
        return deletedTogether.flatMap { ($0.pages ?? []).filter { $0.deletedAt == deletedAt } }
    }

    /// The notes filed directly in this folder that went to Recently Deleted
    /// with it, not those of the folders below it.
    fileprivate var notesDeletedWithItself: [Page] {
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
            // What was inside moves up one level, to where the folder was.
            let parent = folder.parent
            for page in folder.pages ?? [] { page.folder = parent }
            for child in folder.subfolders ?? [] { child.parent = parent }
            context.delete(folder)
        case .withNotes:
            // The folder, the folders in it and every live note in any of them,
            // under one date. A folder already in Recently Deleted keeps its own.
            for member in [folder] + folder.descendants.live {
                for page in member.livePages { page.deletedAt = now }
                if member.isLive { member.deletedAt = now }
            }
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
            for member in folder.deletedTogether {
                member.deletedAt = nil
            }
            // Not into a folder the reader can't see.
            if let parent = folder.parent, !parent.isLive { folder.parent = nil }
        }
        try context.save()
    }

    /// Deletes folders in Recently Deleted for good, with the notes that went
    /// with them, and saves. Reads nothing from the notes, as `Page.delete`
    /// doesn't.
    static func deleteForGood(_ folders: some Sequence<Folder>, from context: ModelContext) throws {
        // The folders below one handed in go with it, and may be handed in too:
        // each is deleted once.
        var done: [Folder] = []
        for folder in folders {
            for member in folder.deletedTogether where !done.contains(where: { $0 === member }) {
                done.append(member)
            }
        }
        for member in done {
            for page in member.notesDeletedWithItself {
                context.delete(page)
            }
        }
        for member in done {
            context.delete(member)
        }
        try context.save()
    }
}

// MARK: - Nesting and order

extension Folder {

    /// This folder's parent, its parent's parent, and so on up.
    var ancestors: [Folder] {
        var found: [Folder] = []
        var current = parent
        // A cycle can't be made through `move`, but a store written some
        // other way shouldn't hang the list.
        while let folder = current, !found.contains(where: { $0 === folder }) {
            found.append(folder)
            current = folder.parent
        }
        return found
    }

    /// Every folder below this one, at any depth, whether or not it is live.
    var descendants: [Folder] {
        var found: [Folder] = []
        var pending = subfolders ?? []
        while let next = pending.popLast() {
            guard !found.contains(where: { $0 === next }), next !== self else { continue }
            found.append(next)
            pending.append(contentsOf: next.subfolders ?? [])
        }
        return found
    }

    /// How many folders are above this one: 0 at the top.
    var depth: Int { ancestors.count }

    /// "CS133 › Labs": the folder's name behind its ancestors', for menus
    /// that list every folder flat.
    var path: String {
        (ancestors.reversed().map(\.name) + [name]).joined(separator: " › ")
    }

    /// Whether the folder may be put inside `target` (or at the top, `nil`):
    /// not inside itself, and not inside anything that is inside it.
    func canMove(into target: Folder?) -> Bool {
        guard let target else { return true }
        return target !== self && !target.ancestors.contains { $0 === self }
    }

    /// The order the reader arranged: by `sortIndex`, then name with numbers
    /// compared as numbers, then age.
    static func arranged(_ folders: [Folder]) -> [Folder] {
        folders.sorted {
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            switch $0.name.localizedStandardCompare($1.name) {
            case .orderedAscending:  return true
            case .orderedDescending: return false
            case .orderedSame:       return $0.createdAt < $1.createdAt
            }
        }
    }

    /// The live folders with the given parent, arranged.
    static func children(of parent: Folder?, in folders: [Folder]) -> [Folder] {
        arranged(folders.live.filter { $0.parent === parent })
    }

    /// Puts `folder` inside `parent` (or at the top), at `index` among the
    /// folders already there (the end when `nil`), and numbers that level
    /// afresh so the order is the reader's from here on.
    ///
    /// The level it leaves is renumbered too, so a gap never opens in an
    /// order that was set by hand.
    ///
    /// - Returns: whether it moved: `false` for a move `canMove(into:)` refuses.
    @discardableResult
    static func move(_ folder: Folder, into parent: Folder?, at index: Int? = nil, among folders: [Folder]) -> Bool {
        guard folder.canMove(into: parent) else { return false }
        let oldParent = folder.parent
        var siblings = children(of: parent, in: folders).filter { $0 !== folder }
        siblings.insert(folder, at: min(max(index ?? siblings.count, 0), siblings.count))
        folder.parent = parent
        for (position, sibling) in siblings.enumerated() { sibling.sortIndex = position }
        if oldParent !== parent {
            // Only if it was arranged already: a level nobody has arranged
            // stays in name order.
            let left = children(of: oldParent, in: folders)
            if left.contains(where: { $0.sortIndex != Int.max }) {
                for (position, sibling) in left.enumerated() { sibling.sortIndex = position }
            }
        }
        return true
    }

    /// The live notes under this folder and every live folder below it. The
    /// count a collapsed folder shows, and what deleting it takes with it.
    var subtreeLivePageCount: Int {
        livePages.count + (subfolders ?? []).live.reduce(0) { $0 + $1.subtreeLivePageCount }
    }

    // MARK: Deleted together

    /// This folder and the folders below it that went to Recently Deleted on
    /// the same date: what deleting it with its notes took along.
    var deletedTogether: [Folder] {
        guard let deletedAt else { return [self] }
        return [self] + descendants.filter { $0.deletedAt == deletedAt }
    }

    /// Whether the folder went to Recently Deleted along with its parent, and
    /// so is held by the parent's row there rather than having one of its own.
    var isDeletedWithParent: Bool {
        guard let deletedAt, let parent, !parent.isLive else { return false }
        return parent.deletedAt == deletedAt
    }
}

extension Sequence where Element == Folder {
    /// The folders that aren't in Recently Deleted. See `Folder.isLive`.
    var live: [Folder] { filter(\.isLive) }
}
