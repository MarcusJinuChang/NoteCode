//
//  RecentlyDeletedView.swift
//  NoteCode
//
//  The notes deleted in the last 30 days, and what can be done with them.
//

import SwiftData
import SwiftUI

/// How a row in Recently Deleted reads. Pure, so the wording is tested.
nonisolated enum RecentlyDeletedCaption {

    /// "Deleted today", "Deleted yesterday", or "Deleted" and the date.
    static func deleted(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Deleted today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Deleted yesterday"
        }
        return "Deleted \(date.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// "30 days left", "1 day left", or, in the last day, that it is.
    static func daysLeft(_ days: Int) -> String {
        switch days {
        case ..<1: "Less than a day left"
        case 1:    "1 day left"
        default:   "\(days) days left"
        }
    }

    static func caption(for page: Page, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let deletedAt = page.deletedAt, let left = page.daysLeft(now: now) else { return "" }
        return "\(deleted(deletedAt, now: now, calendar: calendar)) · \(daysLeft(left))"
    }

    /// A folder's row: how many notes went with it, then the same dates.
    static func caption(for folder: Folder, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let deletedAt = folder.deletedAt, let left = folder.daysLeft(now: now) else { return "" }
        let count = folder.notesDeletedWithIt.count
        let notes = count == 1 ? "1 note" : "\(count) notes"
        return "\(notes) · \(deleted(deletedAt, now: now, calendar: calendar)) · \(daysLeft(left))"
    }
}

/// Recently Deleted, as a sheet over the list: the newest deletion first, each
/// note with Restore and Delete Now (held, or swiped), and Delete All… at the
/// foot, which asks first.
///
/// It runs its own query for the deleted notes rather than being handed the
/// list's, so a note it deletes for good is gone from its rows in the same
/// update, and nothing reads a model whose deletion has been saved.
struct RecentlyDeletedView: View {
    var body: some View {
        NavigationStack {
            RecentlyDeletedPage(showsDone: true)
        }
        .presentationSizing(.form)
    }
}

/// The page itself, without a stack of its own, so Settings can push it
/// (`showsDone` false: the back button leaves it) and the list's sheet can wrap
/// it in one.
struct RecentlyDeletedPage: View {
    var showsDone: Bool

    @AppStorage(AccentPalette.defaultsKey) private var accent = ""

    @Query(filter: Page.deletedPredicate, sort: \Page.deletedAt, order: .reverse)
    private var allDeletedPages: [Page]

    @Query(filter: Folder.deletedPredicate, sort: \Folder.deletedAt, order: .reverse)
    private var allDeletedFolders: [Folder]

    /// The folders with a row of their own: not the ones that went with a
    /// folder they were in, which that folder's row holds.
    private var deletedFolders: [Folder] { allDeletedFolders.filter { !$0.isDeletedWithParent } }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var confirmsDeleteAll = false

    /// The notes with a row of their own: not the ones that went with a folder,
    /// which the folder's row holds.
    private var deleted: [Page] { allDeletedPages.filter { !$0.isDeletedWithFolder } }

    private var isEmpty: Bool { deleted.isEmpty && deletedFolders.isEmpty }

    var body: some View {
        Group {
            List {
                Section {
                    ForEach(deletedFolders) { folder in
                        row(folder)
                    }
                    ForEach(deleted) { page in
                        row(page)
                    }
                } footer: {
                    Text("Notes and folders are deleted for good 30 days after you delete them.")
                }
            }
            .overlay {
                if isEmpty {
                    ContentUnavailableView {
                        Label { Text("Nothing Deleted") } icon: { EmptyStateMark() }
                    } description: {
                        Text("Notes you delete wait here for 30 days.")
                    }
                }
            }
            .navigationTitle("Recently Deleted")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isEmpty {
                    Button("Delete All…", role: .destructive) { confirmsDeleteAll = true }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(.bar)
                        .accessibilityIdentifier("deleteAllButton")
                }
            }
            .confirmationDialog(
                "Delete everything in Recently Deleted for good?",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive, action: deleteAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func row(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(page.title)
                .font(.headline)
            Text(RecentlyDeletedCaption.caption(for: page))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Restore", systemImage: "arrow.uturn.backward") { restore(page) }
            Divider()
            Button("Delete Now", systemImage: "trash", role: .destructive) { deleteNow(page) }
        }
        .swipeActions(edge: .leading) {
            Button("Restore", systemImage: "arrow.uturn.backward") { restore(page) }
                .tint(Color.accent(stored: accent))
        }
        .swipeActions(edge: .trailing) {
            Button("Delete Now", systemImage: "trash", role: .destructive) { deleteNow(page) }
        }
    }

    private func row(_ folder: Folder) -> some View {
        HStack(spacing: 12) {
            FolderBadge(folder: folder)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .font(.headline)
                Text(RecentlyDeletedCaption.caption(for: folder))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Restore", systemImage: "arrow.uturn.backward") { restore(folder) }
            Divider()
            Button("Delete Now", systemImage: "trash", role: .destructive) { deleteNow(folder) }
        }
        .swipeActions(edge: .leading) {
            Button("Restore", systemImage: "arrow.uturn.backward") { restore(folder) }
                .tint(Color.accent(stored: accent))
        }
        .swipeActions(edge: .trailing) {
            Button("Delete Now", systemImage: "trash", role: .destructive) { deleteNow(folder) }
        }
    }

    private func restore(_ folder: Folder) {
        withAnimation { try? Folder.restore([folder], in: modelContext) }
    }

    private func deleteNow(_ folder: Folder) {
        withAnimation { try? Folder.deleteForGood([folder], from: modelContext) }
    }

    private func restore(_ page: Page) {
        withAnimation { try? Page.restore([page], in: modelContext) }
    }

    /// Hard-deletes through `Page.delete`, which reads nothing from the note.
    private func deleteNow(_ page: Page) {
        withAnimation { try? Page.delete([page], from: modelContext) }
    }

    private func deleteAll() {
        let folders = allDeletedFolders
        let pages = allDeletedPages
        withAnimation {
            // Folders first, with the notes that went with them, so no note is
            // deleted twice; then every note left.
            try? Folder.deleteForGood(folders, from: modelContext)
            try? Page.delete(pages.filter { $0.modelContext != nil && !$0.isDeleted }, from: modelContext)
        }
    }
}
