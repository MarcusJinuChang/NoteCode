//
//  NoteTitleMenu.swift
//  NoteCode
//
//  The menu under the open note's title.
//

import SwiftUI

/// What the menu under the open note's title offers: the same rows as the
/// note's long-press menu in the list, plus Rename.
///
/// Passed to `toolbarTitleMenu`, which shows the navigation title with a
/// chevron and opens this when it's tapped. `RenameButton` is the system's own:
/// it edits the title in place, through the binding given to `navigationTitle`.
///
/// Nothing here writes `modifiedAt`. Pinning, locking and moving aren't edits
/// (see "Organising notes" in AGENTS.md), and renaming is picked up from the
/// title's change by `PageDetailView`.
struct NoteTitleMenu: View {
    let page: Page

    /// Every folder, for "Move to Folder".
    let folders: [Folder]

    var onNewFolder: () -> Void
    var onGetInfo: () -> Void

    /// `nil` where the caller can't close the note, which hides Delete.
    var onDelete: (() -> Void)?

    var body: some View {
        // Locking the text locks the title with it.
        RenameButton()
            .disabled(page.isTextLocked)

        Button(page.isPinned ? "Unpin" : "Pin", systemImage: page.isPinned ? "pin.slash" : "pin") {
            withAnimation { page.isPinned.toggle() }
        }

        Menu("Move to Folder", systemImage: "folder") {
            ForEach(NoteListSections(pages: [], folders: folders).allFolders) { folder in
                Button(folder.name) {
                    withAnimation { page.folder = folder }
                }
                .disabled(page.folder == folder)
            }
            Divider()
            Button("New Folder…", systemImage: "folder.badge.plus", action: onNewFolder)
        }

        if page.folder != nil {
            Button("Remove from Folder", systemImage: "folder.badge.minus") {
                withAnimation { page.folder = nil }
            }
        }

        Button(
            page.isTextLocked ? "Unlock Text" : "Lock Text",
            systemImage: page.isTextLocked ? "lock.open" : "lock"
        ) {
            page.isTextLocked.toggle()
        }

        Button("Get Info", systemImage: "info.circle", action: onGetInfo)

        if let onDelete {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// Starts the system's rename on the title as it appears. Invisible; present
/// only for a note just made.
///
/// The action comes from the environment, and only a view under the
/// `navigationTitle` that has the binding sees it, which is why this is a view
/// of its own rather than a line in `PageDetailView`.
struct RenameOnAppear: View {
    @Environment(\.rename) private var rename

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task { rename?() }
    }
}
