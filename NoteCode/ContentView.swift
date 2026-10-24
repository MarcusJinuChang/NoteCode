//
//  ContentView.swift
//  NoteCode
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    /// True when the on-disk store failed and edits live only in memory.
    var storageIsEphemeral = false

    /// The open note. Held as the model object rather than its
    /// `persistentModelID`, which changes from a temporary ID to a permanent
    /// one on first save — a new note would close itself a moment after
    /// opening.
    @State private var selection: Page?

    /// The app opens on Home with the list beside it (`SidebarPlan`); over a
    /// note the list is away until ☰ brings it over the page.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// In a compact width (an iPhone, a folded Duo) there is no room for the
    /// list over the page, so the window is a stack instead: Home at its root,
    /// the list pushed on it, a note pushed on either (roadmap step 11). What
    /// is pushed, kept in step with `selection` and with the split view's
    /// `columnVisibility`, so a Duo folding or unfolding keeps its place.
    @State private var compactPath: [CompactScreen] = []

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
#else
    private var isCompact: Bool { false }
#endif

    /// Whether the title screen is over the window. Raised on a first launch
    /// and by Settings › Help and About › Welcome Screen.
    @State private var showsWelcomeScreen = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// Whether Export All's sheet and the Files picker for Import are showing.
    @State private var showsExportAll = false
    @State private var showsImporter = false

    /// What an import couldn't bring in, for an alert. `nil` when nothing.
    @State private var importProblems: String?

    /// This window's identity in `OpenNoteRegistry`, and the note it has
    /// claimed there, so a second window never edits the same note.
    @State private var window = WindowToken()
    @State private var claimedKey: String?
    private let openNotes = OpenNoteRegistry.shared

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
        // Home has the list beside it; a note opened at launch has it away,
        // unless storage failed, when the warning is the list's.
        _columnVisibility = State(initialValue: storageIsEphemeral ? .all : .detailOnly)
        _compactPath = State(initialValue: openedPage != nil ? [.note] : storageIsEphemeral ? [.list] : [])
    }

    var body: some View {
        navigation
        .environment(toasts)
        .overlay {
            if showsWelcomeScreen {
                WelcomeScreen(onGetStarted: dismissWelcomeScreen)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .settingsSheet(
            isPresented: $showsSettings,
            onOpenWelcomeNote: openWelcomeNote,
            onShowWelcomeScreen: showWelcomeScreen,
            onExportFinished: exported,
            hotbarCanMove: !isCompact
        )
        .sheet(isPresented: $showsExportAll) {
            ExportAllSheet(onFinished: { count in
                showsExportAll = false
                exported(count)
            })
            .presentationSizing(.form)
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: NoteImport.contentTypes,
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .alert("Some files weren't imported", isPresented: Binding(
            get: { importProblems != nil },
            set: { if !$0 { importProblems = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importProblems ?? "")
        }
        .windowActions(WindowActions(
            newNote: newNote,
            newFolder: { ask(.newFolder) },
            searchNotes: { ask(.searchNotes) },
            toggleNoteList: toggleNoteList,
            goHome: goHome,
            isCovered: showsSettings || showsWelcomeScreen
        ))
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            if selection == nil { columnVisibility = .all }
            syncOpenNoteClaim()
            claimWelcomeScreenOnFirstLaunch()
            makeWelcomeNoteOnFirstLaunch()
            purgeExpiredNotes()
            pruneNoteMemory()
        }
        .onChange(of: selection) {
            if selection != newPage { newPage = nil }
            syncOpenNoteClaim()
            if let selection {
                NoteMemory().rememberOpened(selection)
                withAnimation { columnVisibility = .detailOnly }
            } else {
                // A note closed: Home, with the list beside it.
                withAnimation { columnVisibility = .all }
            }
            if isCompact { syncCompactPath(toSelection: selection) }
        }
        // Back from a note, in the stack: the note closes.
        .onChange(of: compactPath) {
            if isCompact, !compactPath.contains(.note), selection != nil {
                selection = nil
            }
        }
        .onChange(of: isCompact) { _, compact in carryPlace(toCompact: compact) }
        // The other window let the note go: it's free to be opened here.
        .onChange(of: isOpenElsewhere) { syncOpenNoteClaim() }
        .onDisappear {
            if let claimedKey { openNotes.release(claimedKey, by: window) }
            claimedKey = nil
        }
    }

    // MARK: Navigation

    /// A split view with the list sliding over the page, or, in a compact
    /// width, a stack.
    @ViewBuilder
    private var navigation: some View {
        if isCompact {
            compactStack
        } else {
            if selection == nil {
                // Home: the list is a column beside it, as in any split view.
                splitView.navigationSplitViewStyle(.balanced)
            } else {
                // A note: the list slides over the page instead of pushing it
                // narrower, so opening it never rescales the note underneath.
                splitView.navigationSplitViewStyle(.prominentDetail)
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            noteList(showsToasts: columnVisibility != .detailOnly)
        } detail: {
            Group {
                if selection != nil {
                    noteDetail
                } else {
                    home
                }
            }
            .overlay(alignment: .bottom) {
                if columnVisibility == .detailOnly {
                    ToastOverlay(center: toasts, bottomInset: selection == nil ? 16 : pageToastInset)
                }
            }
        }
    }

    /// Home, the list and a note, one pushed on another. The back button
    /// takes the place of ☰ and the house, so the note's header has neither.
    private var compactStack: some View {
        NavigationStack(path: $compactPath) {
            home
                .navigationDestination(for: CompactScreen.self) { screen in
                    switch screen {
                    case .list: noteList(showsToasts: true)
                    case .note: noteDetail
                    }
                }
        }
        .overlay(alignment: .bottom) {
            // The list draws its own.
            if compactPath.last != .list {
                ToastOverlay(center: toasts, bottomInset: selection == nil ? 16 : pageToastInset)
            }
        }
    }

    private func noteList(showsToasts: Bool) -> some View {
        NoteList(
            storageIsEphemeral: storageIsEphemeral,
            selection: opening,
            searchText: $searchText,
            onNewPage: { newPage = $0 },
            onShowSettings: { showsSettings = true },
            onImport: { showsImporter = true },
            onExportAll: { showsExportAll = true },
            request: $listRequest,
            showsToasts: showsToasts
        )
            // Searching the list brings the keyboard up; the list stays its
            // size and the keyboard covers its lower rows.
            .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private var noteDetail: some View {
        if let page = selection, isOpenElsewhere {
            OpenElsewhereView(title: page.title, onGoHome: goHome)
        } else if let page = selection {
            PageDetailView(
                page: page,
                revealing: openedSearch,
                onDelete: { delete(page) },
                onGoHome: houseButtonAction,
                onShowSettings: { showsSettings = true },
                startsRenaming: page == newPage
            )
                // A fresh editor per note. Reusing one would carry the last
                // note's undo stack across, and undo would type it back in.
                .id(ObjectIdentifier(page))
        }
    }

    /// The house in a note's header. Not in the stack, whose back button
    /// goes to the list or Home.
    private var houseButtonAction: (() -> Void)? {
        if isCompact { return nil }
        return { goHome() }
    }

    private var home: some View {
        HomeView(
            onOpen: open,
            onNewNote: newNote,
            onNewNoteFromTemplate: { newNote(from: $0) },
            onImport: { showsImporter = true },
            onShowList: showList,
            onShowFolder: { ask(.showFolder($0.persistentModelID)) },
            onSearch: { ask(.searchNotes) },
            onShowSettings: { showsSettings = true },
            onOpenWelcomeNote: openWelcomeNote
        )
    }

    /// Keeps the stack's top in step with the open note: a note opened
    /// anywhere is pushed, a note closed (Home, Delete) is popped, and the
    /// back button closing it clears the selection.
    private func syncCompactPath(toSelection selection: Page?) {
        let path = CompactScreen.path(compactPath, noteOpen: selection != nil)
        if path != compactPath { compactPath = path }
    }

    /// The Duo folding or unfolding: the stack or the split view picks up
    /// what the other was showing.
    private func carryPlace(toCompact compact: Bool) {
        if compact {
            compactPath = CompactScreen.path(
                listShowing: SidebarPlan.stackShowsList(listShowing: columnVisibility != .detailOnly, noteOpen: selection != nil),
                noteOpen: selection != nil
            )
        } else {
            columnVisibility = SidebarPlan.showsList(unfoldingFrom: compactPath, noteOpen: selection != nil) ? .all : .detailOnly
        }
    }

    // MARK: One editor per note

    /// Whether another window has the open note, so this one shows
    /// "Open in another window" instead of a second editor.
    private var isOpenElsewhere: Bool {
        guard let selection, let key = NoteMemory.key(for: selection.persistentModelID) else { return false }
        return openNotes.isOpenElsewhere(key, for: window)
    }

    /// Keeps this window's claim in step with its selection: gives up the
    /// note it left, takes the one it opened if no other window has it.
    private func syncOpenNoteClaim() {
        let key = selection?.settledID.flatMap(NoteMemory.key(for:))
        if let claimedKey, claimedKey != key {
            openNotes.release(claimedKey, by: window)
            self.claimedKey = nil
        }
        if let key, openNotes.claim(key, for: window) {
            claimedKey = key
        }
    }

    // MARK: Import and export

    /// Makes a note of each file the reader chose, in the open note's folder
    /// (or the top of the list), like a new note. One file opens; several are
    /// left in the list, with a toast saying how many and where.
    private func importFiles(_ result: Result<[URL], Error>) {
        let urls: [URL]
        switch result {
        case .success(let chosen): urls = chosen
        case .failure(let error):
            importProblems = error.localizedDescription
            return
        }
        let folder = NewNotes.folder(whileViewing: selection)
        let imported = Page.importFiles(
            urls,
            orientation: newNoteOrientation,
            into: folder,
            context: modelContext
        )
        importProblems = imported.skippedMessage
        if let summary = imported.summary(into: folder) {
            toasts.show(summary)
        }
        if imported.pages.count == 1, let page = imported.pages.first {
            open(page)
        }
    }

    /// Told Export All has written its notes where the reader chose.
    private func exported(_ count: Int) {
        toasts.show(count == 1 ? "Exported 1 note" : "Exported \(count) notes")
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

    /// A note from a template, made and opened the way ⌘N makes one.
    private func newNote(from template: NoteTemplate) {
        let page = Page.create(
            from: template,
            orientation: newNoteOrientation,
            in: NewNotes.folder(whileViewing: selection),
            context: modelContext
        )
        newPage = page
        openedSearch = NoteSearch("")
        selection = page
    }

    /// Opens a note from Home. Not from a search: Home has none, so the note
    /// shows no matches.
    private func open(_ page: Page) {
        openedSearch = NoteSearch("")
        selection = page
    }

    /// Closes the open note and shows Home, with the list beside it: the
    /// house in a note's header, and ⇧⌘H.
    private func goHome() {
        selection = nil
        withAnimation { columnVisibility = .all }
        compactPath = []
    }

    /// Home's Show All: the list over Home.
    private func showList() {
        if isCompact {
            compactPath = [.list]
        } else {
            withAnimation { columnVisibility = .all }
        }
    }

    /// ⇧⌘N and ⇧⌘F belong to the list, so it comes first.
    private func ask(_ request: ListRequest) {
        showList()
        listRequest = request
    }

    /// ⌃⌘S: the list over the page, or away. Over Home too, which is what is
    /// there with no note open.
    private func toggleNoteList() {
        if isCompact {
            compactPath = compactPath.last == .list ? Array(compactPath.dropLast()) : [.list]
            return
        }
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

    /// Raises the title screen on a first launch, once.
    ///
    /// Not when the on-disk store failed or a debug launch opened a note of its
    /// own, for the reason `makeWelcomeNoteOnFirstLaunch` gives, and the turn
    /// isn't spent then.
    private func claimWelcomeScreenOnFirstLaunch() {
        guard !storageIsEphemeral, !opensDebugNote else { return }
        if WelcomeScreen.claimFirstLaunch() {
            withAnimation { showsWelcomeScreen = true }
        }
    }

    private func showWelcomeScreen() {
        withAnimation { showsWelcomeScreen = true }
    }

    private func dismissWelcomeScreen() {
        withAnimation { showsWelcomeScreen = false }
    }

    /// Forgets the places of notes that are gone, once a launch.
    private func pruneNoteMemory() {
        guard !storageIsEphemeral, !opensDebugNote,
              let ids = try? modelContext.fetchIdentifiers(FetchDescriptor<Page>())
        else { return }
        NoteMemory().prune(keeping: Set(ids))
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
        // The bar and its margin, which `keyboardClearance` also reserves,
        // then a gap of the same size.
        dock == .bottom || isCompact ? Hotbar.barFootprint + Hotbar.margin : 16
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
        // In the stack, back to the list, as the split view brings it over.
        compactPath = [.list]
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

/// Shown in place of the editor when another window has the note open, so
/// two editors never write one note (`OpenNoteRegistry`).
struct OpenElsewhereView: View {
    var title: String
    var onGoHome: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label { Text("Open in Another Window") } icon: { EmptyStateMark() }
        } description: {
            Text("\u{201C}\(title)\u{201D} is open in another window. Close it there to edit it here, or open a different note.")
        } actions: {
            Button("Go Home", action: onGoHome)
        }
        .accessibilityIdentifier("openElsewhere")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Page.self, Folder.self], inMemory: true)
}
