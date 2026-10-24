//
//  NoteListSections.swift
//  NoteCode
//

import Foundation
import SwiftData

/// The note list's rows, worked out from every note and folder.
///
/// Pure, so the list's order is tested without SwiftUI.
///
/// One list, not two: at every level a folder is a row among the notes, and
/// the reader's `NoteSort` orders them together (`items`). Nothing puts
/// folders first, so by date a folder sits where its newest note puts it.
///
/// - **Pinned** comes first: pinned folders and pinned notes from anywhere,
///   sorted together (`pinnedItems`). A pinned note is listed there and not
///   again in its folder, so no note has two rows, and a folder's count is the
///   notes under its own row.
/// - **The rest** (`items`) are the folders at the top and the notes in no
///   folder, sorted together. A folder's own `items` are the folders and notes
///   in it, sorted together, and a pinned folder is listed in Pinned and not
///   again in its parent.
///
/// `folders`, `unfiled`, and a section's `notes` and `children` are the same
/// rows grouped by kind, each in sort order.
///
/// Notes in Recently Deleted are left out of all of it (`Page.isLive`), so the
/// list can be handed every note and show only the ones the reader has.
struct NoteListSections {
    /// A row of the list at one level: a folder or a note.
    enum Item: Identifiable {
        case folder(FolderSection)
        case note(Page)

        var id: NoteListRow.ID {
            switch self {
            case .folder(let section): .folder(section.id)
            case .note(let page):      .note(page.persistentModelID)
            }
        }
    }

    struct FolderSection: Identifiable {
        let folder: Folder
        /// The folder's own notes, less any that are pinned.
        let notes: [Page]
        /// The folders in it, less any that are pinned.
        let children: [FolderSection]
        /// Both, sorted together: what the folder shows when it is open.
        let items: [Item]
        var id: PersistentIdentifier { folder.persistentModelID }

        /// The notes under this row and the rows below it, which is what a
        /// folder's count shows.
        var noteCount: Int { notes.count + children.reduce(0) { $0 + $1.noteCount } }
    }

    let pinnedFolders: [FolderSection]
    let pinnedNotes: [Page]

    /// The Pinned section's rows: pinned folders and notes, sorted together.
    let pinnedItems: [Item]

    /// Folders that aren't pinned.
    let folders: [FolderSection]

    /// Notes in no folder and not pinned.
    let unfiled: [Page]

    /// The list's top level: `folders` and `unfiled`, sorted together.
    let items: [Item]

    /// Whether anything is pinned, which is when the Pinned section shows.
    var hasPinned: Bool { !pinnedFolders.isEmpty || !pinnedNotes.isEmpty }

    init(pages: [Page], folders: [Folder], sort: NoteSort = .default) {
        let sorted = pages.live.sorted {
            sort.areInIncreasingOrder(
                ($0.title, $0.modifiedAt, $0.createdAt),
                ($1.title, $1.modifiedAt, $1.createdAt)
            )
        }

        var notesByFolder: [PersistentIdentifier: [Page]] = [:]
        var pinnedNotes: [Page] = []
        var unfiled: [Page] = []
        for page in sorted {
            if page.isPinned {
                pinnedNotes.append(page)
            } else if let folder = page.folder {
                notesByFolder[folder.persistentModelID, default: []].append(page)
            } else {
                unfiled.append(page)
            }
        }

        let live = folders.live

        // A folder's date is its newest note's, anywhere under it, or its own
        // creation when it holds none, so sorting by date moves a folder when
        // a note in it is edited.
        var newest: [PersistentIdentifier: Date] = [:]
        func lastModified(_ folder: Folder) -> Date {
            if let known = newest[folder.persistentModelID] { return known }
            var latest = folder.livePages.map(\.modifiedAt).max() ?? folder.createdAt
            for child in (folder.subfolders ?? []).live {
                latest = max(latest, lastModified(child))
            }
            newest[folder.persistentModelID] = latest
            return latest
        }
        func areInOrder(_ a: Item, _ b: Item) -> Bool {
            func keys(_ item: Item) -> (title: String, modified: Date, created: Date) {
                switch item {
                case .folder(let section):
                    (section.folder.name, lastModified(section.folder), section.folder.createdAt)
                case .note(let page):
                    (page.title, page.modifiedAt, page.createdAt)
                }
            }
            return sort.areInIncreasingOrder(keys(a), keys(b))
        }
        func ordered(_ sections: [FolderSection], _ notes: [Page]) -> [Item] {
            (sections.map(Item.folder) + notes.map(Item.note)).sorted(by: areInOrder)
        }

        func section(_ folder: Folder) -> FolderSection {
            let notes = notesByFolder[folder.persistentModelID] ?? []
            let children = Folder.arranged((folder.subfolders ?? []).live.filter { !$0.isPinned }).map(section)
            return FolderSection(
                folder: folder,
                notes: notes,
                children: children.sorted { areInOrder(.folder($0), .folder($1)) },
                items: ordered(children, notes)
            )
        }

        // A folder whose parent isn't live is at the top as far as the reader
        // can see (a parent only leaves while its folders go with it, but a
        // store written some other way shouldn't lose one).
        let isRoot = { (folder: Folder) in folder.parent.map { !$0.isLive } ?? true }
        let pinnedSections = Folder.arranged(live.filter(\.isPinned)).map(section)
        let rootSections = Folder.arranged(live.filter { isRoot($0) && !$0.isPinned }).map(section)
        self.pinnedFolders = pinnedSections.sorted { areInOrder(.folder($0), .folder($1)) }
        self.pinnedNotes = pinnedNotes
        self.pinnedItems = ordered(pinnedSections, pinnedNotes)
        self.folders = rootSections.sorted { areInOrder(.folder($0), .folder($1)) }
        self.unfiled = unfiled
        self.items = ordered(rootSections, unfiled)
        self.allFolders = live.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    /// Every live folder, at any depth, in path order, for "Move to Folder".
    let allFolders: [Folder]
}

// MARK: - Rows

/// The list's rows for a set of folder sections, open or closed: what the
/// list draws, flattened so every row can be dragged and dropped on.
///
/// Pure, so what shows under a closed folder is tested without SwiftUI.
enum NoteListRow: Identifiable {
    case folder(NoteListSections.FolderSection, depth: Int, isOpen: Bool)
    case note(Page, depth: Int, showsFolder: Bool)
    /// What an open folder with nothing in it shows. Not selectable.
    case empty(Folder, depth: Int)

    enum ID: Hashable {
        case folder(PersistentIdentifier)
        case note(PersistentIdentifier)
        case empty(PersistentIdentifier)
    }

    var id: ID {
        switch self {
        case .folder(let section, _, _): .folder(section.id)
        case .note(let page, _, _):      .note(page.persistentModelID)
        case .empty(let folder, _):      .empty(folder.persistentModelID)
        }
    }

    var depth: Int {
        switch self {
        case .folder(_, let depth, _), .note(_, let depth, _), .empty(_, let depth): depth
        }
    }

    /// The rows for `items` starting at `depth`: each folder, then if it is
    /// open what is in it (its own `items`, or "No Notes"), one level down.
    ///
    /// - Parameter showsFolder: whether the notes at this level name their
    ///   folder, for the Pinned section, where notes from every folder sit
    ///   together. Notes inside an open folder never do.
    static func rows(
        for items: [NoteListSections.Item],
        closed: Set<PersistentIdentifier>,
        depth: Int = 0,
        showsFolder: Bool = false
    ) -> [NoteListRow] {
        items.flatMap { item -> [NoteListRow] in
            switch item {
            case .note(let page):
                return [.note(page, depth: depth, showsFolder: showsFolder)]
            case .folder(let section):
                let isOpen = !closed.contains(section.id)
                var rows: [NoteListRow] = [.folder(section, depth: depth, isOpen: isOpen)]
                guard isOpen else { return rows }
                rows += Self.rows(for: section.items, closed: closed, depth: depth + 1)
                if section.items.isEmpty {
                    rows.append(.empty(section.folder, depth: depth + 1))
                }
                return rows
            }
        }
    }
}
