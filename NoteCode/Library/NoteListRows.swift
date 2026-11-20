//
//  NoteListRows.swift
//  NoteCode
//
//  The note list's rows and their menus, each a type that takes what it reads
//  as `let`s and what it does as closures (2P4, which took over 1B6).
//

import SwiftData
import SwiftUI

/// Sizes shared by the rows.
enum NoteListMetrics {
    /// A row's picture of the note's first page: 30 by 39 (the `Library`
    /// board), Letter's proportions.
    static let thumbnailSize = CGSize(width: 30, height: 39)

    /// How far a row is pushed in for each folder above it.
    static func indent(_ depth: Int) -> CGFloat {
        CGFloat(min(depth, 6)) * 18
    }
}

/// The selected note's row is the accent at a low strength, with the label
/// colour kept for its text: never white on solid orange.
private struct SelectedRowBackground: ViewModifier {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingKeys.General.accent) private var accent

    func body(content: Content) -> some View {
        content.listRowBackground(
            isSelected ? RowSelectionTint.color(isDark: colorScheme == .dark, accent: accent) : nil
        )
    }
}

/// One note's row, at `depth` folders down. Dragged to file it, and a drop
/// target itself: dropped on, it files the other note beside it.
struct NoteRow: View {
    let page: Page
    let depth: Int
    let showsFolder: Bool
    let sort: NoteSort
    let isSelected: Bool
    let drag: ListDragState
    let menu: NoteMenu
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NoteThumbnailView(page: page)
                .frame(width: NoteListMetrics.thumbnailSize.width, height: NoteListMetrics.thumbnailSize.height)
            VStack(alignment: .leading) {
                Text(page.displayTitle)
                    .font(.headline)
                HStack(spacing: 4) {
                    if page.isTextLocked {
                        Image(systemName: "lock.fill")
                            .accessibilityLabel("Text Locked")
                    }
                    if showsFolder, let folder = page.folder {
                        Text(folder.name)
                        Text("·")
                    }
                    // The date the list is sorted by, so the order can be read
                    // off the rows.
                    Text(
                        sort.displayedDate(modified: page.modifiedAt, created: page.createdAt),
                        format: Date.FormatStyle(date: .abbreviated, time: .shortened)
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, NoteListMetrics.indent(depth))
        .opensOnTapInCompactWidth(onOpen)
        .contextMenu { menu }
        .onDrag { drag.lift(.note(page)) }
        .modifier(ListRowDrop(
            target: .note(page), hoverID: .row(.note(page.persistentModelID)), drag: drag
        ))
        // The tag and the row background last, outside the drag and the
        // drop: under them the sidebar never selected the row on a tap, so
        // it opened nothing, and its tint didn't show (simulator, 7 Nov).
        .tag(page)
        .modifier(SelectedRowBackground(isSelected: isSelected))
    }
}

/// A search result's row: the note's title, the line it matched on, and where
/// it's filed, with the words searched for in bold.
struct NoteResultRow: View {
    let result: NoteSearch.Result
    let search: NoteSearch
    let sort: NoteSort
    let isSelected: Bool
    let menu: NoteMenu
    var onOpen: () -> Void

    var body: some View {
        let page = result.page
        HStack(spacing: 12) {
            NoteThumbnailView(page: page)
                .frame(width: NoteListMetrics.thumbnailSize.width, height: NoteListMetrics.thumbnailSize.height)
            VStack(alignment: .leading, spacing: 2) {
                Text(search.highlighted(page.displayTitle))
                    .font(.headline)
                if let excerpt = result.match.excerpt {
                    Text(search.highlighted(excerpt))
                        .font(.subheadline)
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    if let folder = page.folder {
                        Text(folder.name)
                        Text("·")
                    }
                    Text(
                        sort.displayedDate(modified: page.modifiedAt, created: page.createdAt),
                        format: Date.FormatStyle(date: .abbreviated, time: .shortened)
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .tag(page)
        .opensOnTapInCompactWidth(onOpen)
        .modifier(SelectedRowBackground(isSelected: isSelected))
        .contextMenu { menu }
    }
}

/// A folder's row: an arrow on the left that opens and closes it, the
/// folder's face and name, and how many notes are under it. A tap anywhere on
/// the row does what the arrow does. Dragged to move or arrange it; dropped
/// on, its top and bottom edges arrange and its middle takes what is dropped
/// (`ListDrop`).
struct FolderRow: View {
    let section: NoteListSections.FolderSection
    let depth: Int
    let isOpen: Bool
    let drag: ListDragState
    let menu: FolderMenu
    /// Whether the delete dialog is up for this folder.
    let isDeleting: Binding<Bool>
    var onToggle: () -> Void
    var onDelete: (Folder.Deletion) -> Void

    var body: some View {
        let folder = section.folder
        HStack(spacing: 4) {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 28, height: TapTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Close \(folder.name)" : "Open \(folder.name)")
            .accessibilityIdentifier("folderArrow")

            HStack(spacing: 10) {
                FolderBadge(folder: folder)
                Text(folder.name)
                    .fontWeight(.semibold)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Text(section.noteCount, format: .number)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, NoteListMetrics.indent(depth))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .deleteDisabled(true)
        .onDrag { drag.lift(.folder(folder)) }
        .modifier(ListRowDrop(
            target: .folder(folder), hoverID: .row(.folder(folder.persistentModelID)), drag: drag
        ))
        .contextMenu { menu }
        // On the row, not the list: on an iPad the dialog is a popover, and
        // attached to the list it pointed at the middle of the list's edge.
        .confirmationDialog(
            "Delete “\(folder.name)”?",
            isPresented: isDeleting,
            titleVisibility: .visible
        ) {
            let count = folder.subtreeLivePageCount
            if count == 0 {
                Button("Delete Folder", role: .destructive) {
                    onDelete(.keepingNotes)
                }
            } else {
                Button("Delete Folder and ^[\(count) Note](inflect: true)", role: .destructive) {
                    onDelete(.withNotes)
                }
                Button("Delete Folder, Keep Notes") {
                    onDelete(.keepingNotes)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if folder.subtreeLivePageCount > 0 || !(folder.subfolders ?? []).isEmpty {
                Text("Kept notes and folders move up one level, to where this folder is. The folder and what is deleted with it wait in Recently Deleted for 30 days.")
            }
        }
    }
}

/// The note's long-press menu is the title menu: the same view, so the same
/// rows in the same order. The list renames through the name alert, since it
/// has no title to edit in place, and deletes without asking, as it always
/// has: the note goes to Recently Deleted, and the toast undoes it.
struct NoteMenu: View {
    let page: Page
    let folders: [Folder]
    var onNewFolder: () -> Void
    var onGetInfo: () -> Void
    var onDuplicate: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    var body: some View {
        NoteTitleMenu(
            page: page,
            folders: folders,
            onNewFolder: onNewFolder,
            onGetInfo: onGetInfo,
            onDuplicate: onDuplicate,
            onRename: onRename,
            onDelete: onDelete
        )
    }
}

/// A folder's long-press menu.
struct FolderMenu: View {
    let folder: Folder
    let folders: [Folder]
    var onRename: () -> Void
    var onNewNote: (PageOrientation) -> Void
    var onNewFolderInside: () -> Void
    /// Moves the folder to the end of another folder, or the top for nil.
    var onMove: (Folder?) -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(
            folder.isPinned ? "Unpin Folder" : "Pin Folder",
            systemImage: folder.isPinned ? "pin.slash" : "pin"
        ) {
            withAnimation { folder.isPinned.toggle() }
        }
        Button("Rename…", systemImage: "pencil", action: onRename)
        Menu("New", systemImage: "plus") {
            NewNoteButtons(onNewNote: onNewNote)
            Divider()
            Button("Folder Inside…", systemImage: "folder.badge.plus", action: onNewFolderInside)
        }
        Divider()
        Menu("Move To", systemImage: "folder") {
            Button("Top Level", systemImage: "tray") {
                onMove(nil)
            }
            .disabled(folder.parent == nil)
            ForEach(folders.live.filter { folder.canMove(into: $0) && $0 !== folder.parent }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) { target in
                Button(target.path) { onMove(target) }
            }
        }
        Divider()
        Button("Delete Folder…", systemImage: "trash", role: .destructive, action: onDelete)
    }
}

/// One button per orientation. Which way up a note's pages are is chosen
/// here, once. Changing it later would re-wrap the text at another width and
/// move every line out from under its ink.
struct NewNoteButtons: View {
    var onNewNote: (PageOrientation) -> Void

    var body: some View {
        ForEach(PageOrientation.allCases, id: \.self) { orientation in
            Button {
                onNewNote(orientation)
            } label: {
                Label("\(orientation.title) Pages", systemImage: orientation.systemImage)
            }
        }
    }
}

/// The selected note's row, behind its text: the accent at 18% in light and
/// 22% in dark, the design's tint (#FFE9CF over white for the default accent).
/// The label colour stays on top, so it reads in both appearances, which solid
/// orange with white text would not for the smaller type.
enum RowSelectionTint {
    static func opacity(isDark: Bool) -> Double {
        isDark ? 0.22 : 0.18
    }

    /// - Parameter accent: the stored accent (`SettingKeys.General.accent.name`).
    static func color(isDark: Bool, accent: String) -> Color {
        Color.accent(stored: accent).opacity(opacity(isDark: isDark))
    }
}

/// Sort By and Order, in the list's menu.
struct NoteSortMenu: View {
    @Binding var sort: NoteSort

    /// Picking a key also picks the way round that reads naturally for it.
    private var sortKey: Binding<NoteSort.Key> {
        Binding { sort.key } set: { sort = sort.with(key: $0) }
    }

    var body: some View {
        Menu {
            Picker("Sort By", selection: sortKey) {
                ForEach(NoteSort.Key.allCases, id: \.self) { key in
                    Text(key.title).tag(key)
                }
            }
            // The way round that reads naturally for the key comes first:
            // newest first for dates, A to Z for titles.
            Picker("Order", selection: $sort.ascending) {
                let natural = sort.key.naturallyAscending
                ForEach([natural, !natural], id: \.self) { ascending in
                    Text(ascending ? sort.orderTitles.ascending : sort.orderTitles.descending)
                        .tag(ascending)
                }
            }
        } label: {
            Label("Sort By", systemImage: "arrow.up.arrow.down")
        }
    }
}
