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
}

/// Recently Deleted, as a sheet over the list: the newest deletion first, each
/// note with Restore and Delete Now (held, or swiped), and Delete All… at the
/// foot, which asks first.
///
/// It runs its own query for the deleted notes rather than being handed the
/// list's, so a note it deletes for good is gone from its rows in the same
/// update, and nothing reads a model whose deletion has been saved.
struct RecentlyDeletedView: View {
    @Query(filter: Page.deletedPredicate, sort: \Page.deletedAt, order: .reverse)
    private var deleted: [Page]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var confirmsDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(deleted) { page in
                        row(page)
                    }
                } footer: {
                    Text("Notes are deleted for good 30 days after you delete them.")
                }
            }
            .overlay {
                if deleted.isEmpty {
                    ContentUnavailableView(
                        "Nothing Deleted",
                        systemImage: "trash",
                        description: Text("Notes you delete wait here for 30 days.")
                    )
                }
            }
            .navigationTitle("Recently Deleted")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !deleted.isEmpty {
                    Button("Delete All…", role: .destructive) { confirmsDeleteAll = true }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(.bar)
                        .accessibilityIdentifier("deleteAllButton")
                }
            }
            .confirmationDialog(
                "Delete ^[\(deleted.count) Note](inflect: true) for good?",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive, action: deleteAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
        .presentationSizing(.form)
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
                .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete Now", systemImage: "trash", role: .destructive) { deleteNow(page) }
        }
    }

    private func restore(_ page: Page) {
        withAnimation { try? Page.restore([page], in: modelContext) }
    }

    /// Hard-deletes through `Page.delete`, which reads nothing from the note.
    private func deleteNow(_ page: Page) {
        withAnimation { try? Page.delete([page], from: modelContext) }
    }

    private func deleteAll() {
        let all = deleted
        withAnimation { try? Page.delete(all, from: modelContext) }
    }
}
