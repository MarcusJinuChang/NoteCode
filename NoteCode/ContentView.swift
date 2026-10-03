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

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    /// - Parameter openedPage: a note to open straight away, with the list
    ///   hidden. Only debug launch arguments pass one.
    init(storageIsEphemeral: Bool = false, openedPage: Page? = nil) {
        self.storageIsEphemeral = storageIsEphemeral
        _selection = State(initialValue: openedPage)
        _columnVisibility = State(initialValue: openedPage == nil ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NoteList(storageIsEphemeral: storageIsEphemeral, selection: $selection)
        } detail: {
            if let page = selection {
                PageDetailView(page: page, toggleSidebar: sidebarToggle)
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
            if selection != nil {
                withAnimation { columnVisibility = .detailOnly }
            }
        }
    }

    /// The note page's ☰ button, where there is a sidebar for it to show.
    private var sidebarToggle: (() -> Void)? {
#if os(iOS)
        guard horizontalSizeClass != .compact else { return nil }
        return {
            withAnimation {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        }
#else
        return nil
#endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Page.self, Folder.self], inMemory: true)
}
