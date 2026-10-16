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
/// - **Pinned** comes first: pinned folders, then pinned notes from anywhere.
///   A pinned note is listed there and not again in its folder, so no note
///   has two rows, and a folder's count is the notes under its own row.
/// - **Folders** are in the reader's order (`Folder.arranged`): the order they
///   were dragged into, or, for a level nobody has arranged, name order, with
///   numbers compared as numbers so "CS 9" comes before "CS 133". The note
///   sort doesn't move them, so they stay where the reader left them. They
///   nest: a folder's `children` are the folders in it, and a pinned folder is
///   listed in Pinned and not again in its parent.
/// - **Notes** in no folder come last.
///
/// Notes are in the reader's `NoteSort` order everywhere.
///
/// Notes in Recently Deleted are left out of all of it (`Page.isLive`), so the
/// list can be handed every note and show only the ones the reader has.
struct NoteListSections {
    struct FolderSection: Identifiable {
        let folder: Folder
        /// The folder's own notes, less any that are pinned.
        let notes: [Page]
        /// The folders in it, arranged, less any that are pinned.
        let children: [FolderSection]
        var id: PersistentIdentifier { folder.persistentModelID }

        /// The notes under this row and the rows below it, which is what a
        /// folder's count shows.
        var noteCount: Int { notes.count + children.reduce(0) { $0 + $1.noteCount } }
    }

    let pinnedFolders: [FolderSection]
    let pinnedNotes: [Page]

    /// Folders that aren't pinned.
    let folders: [FolderSection]

    /// Notes in no folder and not pinned.
    let unfiled: [Page]

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
        func section(_ folder: Folder) -> FolderSection {
            FolderSection(
                folder: folder,
                notes: notesByFolder[folder.persistentModelID] ?? [],
                children: Folder.arranged((folder.subfolders ?? []).live.filter { !$0.isPinned }).map(section)
            )
        }

        // A folder whose parent isn't live is at the top as far as the reader
        // can see (a parent only leaves while its folders go with it, but a
        // store written some other way shouldn't lose one).
        let isRoot = { (folder: Folder) in folder.parent.map { !$0.isLive } ?? true }
        self.pinnedFolders = Folder.arranged(live.filter(\.isPinned)).map(section)
        self.pinnedNotes = pinnedNotes
        self.folders = Folder.arranged(live.filter { isRoot($0) && !$0.isPinned }).map(section)
        self.unfiled = unfiled
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

    /// The rows for `sections` starting at `depth`: each folder, then if it is
    /// open the folders in it, then its notes (or "No Notes").
    static func rows(
        for sections: [NoteListSections.FolderSection],
        closed: Set<PersistentIdentifier>,
        depth: Int = 0
    ) -> [NoteListRow] {
        sections.flatMap { section -> [NoteListRow] in
            let isOpen = !closed.contains(section.id)
            var rows: [NoteListRow] = [.folder(section, depth: depth, isOpen: isOpen)]
            guard isOpen else { return rows }
            rows += Self.rows(for: section.children, closed: closed, depth: depth + 1)
            rows += section.notes.map { .note($0, depth: depth + 1, showsFolder: false) }
            if section.children.isEmpty && section.notes.isEmpty {
                rows.append(.empty(section.folder, depth: depth + 1))
            }
            return rows
        }
    }
}
