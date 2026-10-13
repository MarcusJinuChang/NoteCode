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

    /// Whether Settings is showing. Held here, above the list, so ⌘, opens it
    /// whether or not the list is on screen.
    @State private var showsSettings = false

    /// Something for the list to do when it is on screen: the menu bar's
    /// New Folder and Search Notes.
    @State private var listRequest: ListRequest?

    /// Which way up ⌘N makes a note's pages (Settings › Notes › New Notes),
    /// as the + button's tap does.
    @AppStorage(NewNotes.defaultsKey) private var newNoteOrientation = PageOrientation.default

    /// The message that follows a deletion, with its Undo. Drawn by the list
    /// when the list is showing and by the open note's page when it isn't.
    @State private var toasts = ToastCenter()

#if canImport(UIKit)
    /// Where the hotbar is docked, so a toast on the page sits clear of it.
    @AppStorage(HotbarDock.defaultsKey) private var dock: HotbarDock = .default
#endif

    @Environment(\.modelContext) private var modelContext

    /// True when a debug launch argument opened a note, in a store of its own.
    private let opensDebugNote: Bool

    /// - Parameter openedPage: a note to open straight away, with the list
    ///   hidden. Only debug launch arguments pass one.
    init(storageIsEphemeral: Bool = false, openedPage: Page? = nil) {
        self.storageIsEphemeral = storageIsEphemeral
        opensDebugNote = openedPage != nil
        _selection = State(initialValue: openedPage)
        _columnVisibility = State(initialValue: openedPage == nil ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NoteList(
                storageIsEphemeral: storageIsEphemeral,
                selection: opening,
                searchText: $searchText,
                onNewPage: { newPage = $0 },
                onShowSettings: { showsSettings = true },
                request: $listRequest,
                showsToasts: columnVisibility != .detailOnly
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
                    .overlay(alignment: .bottom) {
                        if columnVisibility == .detailOnly {
                            ToastOverlay(center: toasts, bottomInset: pageToastInset)
                        }
                    }
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
        .environment(toasts)
        .settingsSheet(isPresented: $showsSettings, onOpenWelcomeNote: openWelcomeNote)
        .windowActions(WindowActions(
            newNote: newNote,
            newFolder: { ask(.newFolder) },
            searchNotes: { ask(.searchNotes) },
            toggleNoteList: toggleNoteList,
            isCovered: showsSettings
        ))
        .task {
            makeWelcomeNoteOnFirstLaunch()
            purgeExpiredNotes()
        }
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

    /// ⌘N: the + button's tap. A note in the open note's folder, opened with
    /// its title ready to rename, through `Page.create` like every other way
    /// of making one.
    private func newNote() {
        let page = Page.create(
            orientation: newNoteOrientation,
            in: NewNotes.folder(whileViewing: selection),
            context: modelContext
        )
        newPage = page
        openedSearch = NoteSearch("")
        selection = page
    }

    /// ⇧⌘N and ⇧⌘F belong to the list, so it comes first.
    private func ask(_ request: ListRequest) {
        withAnimation { columnVisibility = .all }
        listRequest = request
    }

    /// ⌃⌘S: the list over the page, or away. With no note open the list is
    /// all there is, and stays.
    private func toggleNoteList() {
        guard selection != nil else { return }
        withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    /// Settings › Help and About › Welcome Note: a new copy each time, opened.
    ///
    /// Opened like a note the reader made, so the list slides away for it.
    /// Other notes are untouched, dates included.
    private func openWelcomeNote() {
        let page = WelcomeNote.make(in: modelContext)
        openedSearch = NoteSearch("")
        selection = page
    }

    /// Gives a first launch its tour. Left in the list rather than opened:
    /// the list is where a new reader should see that there's a list.
    ///
    /// Not when the on-disk store failed: the note would live in memory for
    /// one session, and the flag would say a first launch had happened. And
    /// not under a debug launch that opened a note of its own, whose store is
    /// in memory and meant to hold exactly that note.
    private func makeWelcomeNoteOnFirstLaunch() {
        guard !storageIsEphemeral, !opensDebugNote else { return }
        WelcomeNote.makeOnFirstLaunch(in: modelContext)
    }

    /// How far above the page's bottom edge a toast sits: clear of the hotbar
    /// when it is docked there.
    private var pageToastInset: CGFloat {
#if canImport(UIKit)
        // The bar's thickness and the 12pt around it that `keyboardClearance`
        // also reserves, then a gap.
        dock == .bottom ? Hotbar.thickness + 12 + 12 : 16
#else
        16
#endif
    }

    /// Deletes notes past their 30 days in Recently Deleted, once a launch.
    ///
    /// After the Welcome note's check, not before: a store whose only notes
    /// were deleted has been used, and the Welcome note's check counts them.
    private func purgeExpiredNotes() {
        try? Page.purgeExpired(in: modelContext)
    }

    /// Closes the open note and moves it to Recently Deleted.
    ///
    /// The note closes first, and the page that shows it with it. The list
    /// comes back, since the page it slid away for is gone and its ☰ with it.
    /// Nothing asks: the toast's Undo puts the note back and, if the reader
    /// hasn't opened another since, reopens it.
    private func delete(_ page: Page) {
        selection = nil
        withAnimation {
            columnVisibility = .all
            // If saving fails, the change is still pending in the context,
            // and autosave tries again.
            try? Page.moveToRecentlyDeleted([page], from: modelContext)
        }
        toasts.show("Moved to Recently Deleted", actionTitle: "Undo") {
            withAnimation { try? Page.restore([page], in: modelContext) }
            if selection == nil {
                openedSearch = NoteSearch("")
                selection = page
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Page.self, Folder.self], inMemory: true)
}
