//
//  NoteTitleMenu.swift
//  NoteCode
//
//  The menu under the open note's title.
//

import SwiftUI

/// What the menu under the open note's title offers, and, since phase 8, what
/// the note's long-press menu in the list offers too: one view, so the two
/// menus can't drift apart in rows or order.
///
/// Passed to `toolbarTitleMenu`, which shows the navigation title with a
/// chevron and opens this when it's tapped. `RenameButton` is the system's own:
/// it edits the title in place, through the binding given to `navigationTitle`.
///
/// Nothing here writes `modifiedAt`. Pinning, locking and moving aren't edits
/// (see "Organising notes" in AGENTS.md), and renaming is picked up from the
/// title's change by `PageDetailView`. Delete moves the note to Recently
/// Deleted without asking; the caller's toast offers the way back.
struct NoteTitleMenu: View {
    let page: Page

    /// Every folder, for "Move to Folder".
    let folders: [Folder]

    var onNewFolder: () -> Void
    var onGetInfo: () -> Void

    /// Makes a copy (`Page.duplicated(in:)`). The caller has the context.
    var onDuplicate: () -> Void

    /// `nil` under a navigation title, where the system's `RenameButton`
    /// edits the title in place. The list has no title to edit, so it passes
    /// an action that asks for a name.
    var onRename: (() -> Void)?

    /// `nil` where the caller can't close the note, which hides Delete.
    var onDelete: (() -> Void)?

    var body: some View {
        // Locking the text locks the title with it.
        if let onRename {
            Button("Rename", systemImage: "pencil", action: onRename)
                .disabled(page.isTextLocked)
        } else {
            RenameButton()
                .disabled(page.isTextLocked)
        }

        Button(page.isPinned ? "Unpin" : "Pin", systemImage: page.isPinned ? "pin.slash" : "pin") {
            withAnimation { page.isPinned.toggle() }
        }

        Menu("Move to Folder", systemImage: "folder") {
            // Top Level is the old "Remove from Folder" row, kept here so the
            // menu stays at six items.
            if page.folder != nil {
                Button("Top Level", systemImage: "tray") {
                    withAnimation { page.folder = nil }
                }
                Divider()
            }
            ForEach(NoteListSections(pages: [], folders: folders).allFolders) { folder in
                Button(folder.path) {
                    withAnimation { page.folder = folder }
                }
                .disabled(page.folder == folder)
            }
            Divider()
            Button("New Folder…", systemImage: "folder.badge.plus", action: onNewFolder)
        }

        Button("Get Info", systemImage: "info.circle", action: onGetInfo)

        Menu("Manage", systemImage: "ellipsis.circle") {
            Button(
                page.isTextLocked ? "Unlock Text" : "Lock Text",
                systemImage: page.isTextLocked ? "lock.open" : "lock"
            ) {
                page.isTextLocked.toggle()
            }
            Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
        }

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
