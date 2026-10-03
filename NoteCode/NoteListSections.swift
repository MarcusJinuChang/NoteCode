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
/// - **Folders** are in name order, the way Files and Notes sort them, with
///   numbers compared as numbers so "CS 9" comes before "CS 133". The note
///   sort doesn't move them, so they stay where the reader left them.
/// - **Notes** in no folder come last.
///
/// Notes are in the reader's `NoteSort` order everywhere.
struct NoteListSections {
    struct FolderSection: Identifiable {
        let folder: Folder
        /// The folder's notes, less any that are pinned.
        let notes: [Page]
        var id: PersistentIdentifier { folder.persistentModelID }
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
        let sorted = pages.sorted {
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

        let sections = folders
            .sorted {
                switch $0.name.localizedStandardCompare($1.name) {
                case .orderedAscending:  true
                case .orderedDescending: false
                case .orderedSame:       $0.createdAt < $1.createdAt
                }
            }
            .map { FolderSection(folder: $0, notes: notesByFolder[$0.persistentModelID] ?? []) }

        self.pinnedFolders = sections.filter(\.folder.isPinned)
        self.pinnedNotes = pinnedNotes
        self.folders = sections.filter { !$0.folder.isPinned }
        self.unfiled = unfiled
    }

    /// Every folder in name order, pinned or not, for "Move to Folder".
    var allFolders: [Folder] {
        (pinnedFolders + folders).map(\.folder).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
