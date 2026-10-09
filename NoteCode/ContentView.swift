//
//  ContentView.swift
//  NoteCode
//

import SwiftUI
import SwiftData

struct ContentView: View {
    /// True when the on-disk store failed and edits live only in memory.
    var storageIsEphemeral = false

    /// The open note. Held as the model object rather than its
    /// `persistentModelID`, which changes from a temporary ID to a permanent
    /// one on first save — a new note would close itself a moment after
    /// opening.
    @State private var selection: Page?

    /// Starts with the list showing, since there's no note open yet.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// What the list's search field holds.
    @State private var searchText = ""

    /// The search the open note was opened from, so it can show where it
    /// matched. Taken as a note opens rather than read live, so typing in
    /// the search field doesn't redraw the note under the list.
    @State private var openedSearch = NoteSearch("")

    /// A note the reader has just made, which opens with its title being
    /// renamed. Cleared when another note opens, so coming back to this one
    /// later doesn't start renaming again.
    @State private var newPage: Page?

    @Environment(\.modelContext) private var modelContext

    /// - Parameter openedPage: a note to open straight away, with the list
    ///   hidden. Only debug launch arguments pass one.
    init(storageIsEphemeral: Bool = false, openedPage: Page? = nil) {
        self.storageIsEphemeral = storageIsEphemeral
        _selection = State(initialValue: openedPage)
        _columnVisibility = State(initialValue: openedPage == nil ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NoteList(
                storageIsEphemeral: storageIsEphemeral,
                selection: opening,
                searchText: $searchText,
                onNewPage: { newPage = $0 }
            )
                // Searching the list brings the keyboard up; the list stays its
                // size and the keyboard covers its lower rows.
                .ignoresSafeArea(.keyboard)
        } detail: {
            if let page = selection {
                PageDetailView(
                    page: page,
                    revealing: openedSearch,
                    onDelete: { delete(page) },
                    startsRenaming: page == newPage
                )
                    // A fresh editor per note. Reusing one would carry the last
                    // note's undo stack across, and undo would type it back in.
                    .id(ObjectIdentifier(page))
            } else {
                ContentUnavailableView(
                    "No Note Open",
                    systemImage: "note.text",
                    description: Text("Choose a note from the list, or start a new one.")
                )
            }
        }
        // The list slides over the page instead of pushing it narrower, so
        // opening it never re-wraps the note underneath.
        .navigationSplitViewStyle(.prominentDetail)
        .onChange(of: selection) {
            if selection != newPage { newPage = nil }
            if selection != nil {
                withAnimation { columnVisibility = .detailOnly }
            }
        }
    }

    /// The list's selection, noting the search each note is opened from.
    ///
    /// While there's a search the list shows only its results, so a note
    /// opened from the list then was opened from a result. Set together with
    /// the selection, so the note's page is made knowing it.
    private var opening: Binding<Page?> {
        Binding {
            selection
        } set: { page in
            openedSearch = NoteSearch(searchText)
            selection = page
        }
    }

    /// Closes the open note and deletes it.
    ///
    /// The note closes first: a deleted note's ink can't be read once the
    /// deletion is saved (see AGENTS.md), and the page that shows it is the
    /// one reading it. The list comes back, since the page it slid away for
    /// is gone and its ☰ with it.
    private func delete(_ page: Page) {
        selection = nil
        withAnimation {
            columnVisibility = .all
            // If saving fails, the deletion is still pending in the context,
            // and autosave tries again.
            try? Page.delete([page], from: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Page.self, Folder.self], inMemory: true)
}
