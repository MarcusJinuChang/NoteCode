//
//  NoteList.swift
//  NoteCode
//
//  The note list: folders, and the notes in and out of them.
//

import SwiftData
import SwiftUI

/// Every note, grouped into folders, in the sidebar the ☰ button opens.
///
/// Folders open and close in place rather than leading to a list of their
/// own. The list slides over the page, and a second column for folders would
/// cover even more of it; with one level of folders, a disclosure row is all
/// the navigation there is. What goes in which section, and in what order, is
/// `NoteListSections`.
struct NoteList: View {
    /// True when the on-disk store failed and edits live only in memory.
    var storageIsEphemeral = false

    @Binding var selection: Page?

    /// What the search field holds. While it holds words, the list shows the
    /// notes that match instead of its folders.
    @Binding var searchText: String

    /// Told of each note the "+" menu makes, so the page can open with its
    /// title ready to type.
    var onNewPage: (Page) -> Void = { _ in }

    /// Asked to show Settings, from the gear at the foot of the list.
    var onShowSettings: () -> Void = {}

    /// Asked to close the open note and show Home: the Home row at the top.
    var onShowHome: () -> Void = {}

    /// What the menu bar has asked the list to do (New Folder, Search Notes).
    /// Answered when the list is on screen, then cleared.
    @Binding var request: ListRequest?

    /// Whether the list is the one to draw the toast: it is when the list is
    /// on screen, and the open note's page draws it when the list is away.
    var showsToasts = true

    init(
        storageIsEphemeral: Bool = false,
        selection: Binding<Page?>,
        searchText: Binding<String>,
        onNewPage: @escaping (Page) -> Void = { _ in },
        onShowSettings: @escaping () -> Void = {},
        onShowHome: @escaping () -> Void = {},
        request: Binding<ListRequest?> = .constant(nil),
        showsToasts: Bool = true
    ) {
        self.storageIsEphemeral = storageIsEphemeral
        _selection = selection
        _searchText = searchText
        self.onNewPage = onNewPage
        self.onShowSettings = onShowSettings
        self.onShowHome = onShowHome
        _request = request
        self.showsToasts = showsToasts
    }

    @FocusState private var searchIsFocused: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    // Every note, deleted ones included: the sections and search leave out
    // what is in Recently Deleted (`Page.live`), and the foot counts it.
    @Query(sort: \Page.modifiedAt, order: .reverse) private var pages: [Page]
    @Query private var folders: [Folder]

    /// How notes are ordered. Per device, like the view mode: it's how this
    /// reader likes to look at the list, and changes nothing in a note.
    @AppStorage(NoteSort.defaultsKey) private var sort: NoteSort = .default

    /// Which way up the "+" button's tap makes a note's pages
    /// (Settings › Notes › New Notes).
    @AppStorage(NewNotes.defaultsKey) private var newNoteOrientation = PageOrientation.default

    /// Where code blocks run when nothing more specific says, for the
    /// folder menu's "Default" row.
    @AppStorage(RunDestinationPreference.appDefaultKey)
    private var appDefaultDestination: String = CodeDestination.default.id

    /// Folders the reader has closed. Folders start open, so a new folder's
    /// notes are never hidden behind a row nobody has tapped yet.
    @State private var closedFolders: Set<PersistentIdentifier> = []

    /// The note the rename alert is for. Kept after the alert closes, since
    /// its button may run after the alert has said it's gone.
    @State private var renamingPage: Page?
    @State private var showsNameAlert = false
    @State private var typedName = ""

    /// The folder editor's sheet: a new folder, or a folder's name, colour
    /// and symbol.
    @State private var editingFolder: FolderEditing?

    /// Whether the Recently Deleted sheet is showing.
    @State private var showsRecentlyDeleted = false

    /// The folder whose deletion is waiting on the reader's choice.
    @State private var deleting: Folder?

    /// The note whose info is showing.
    @State private var infoPage: Page?

#if os(iOS)
    /// Held here rather than left to an `EditButton`, since editing starts
    /// from the list's menu and ends at the Done that replaces it.
    @State private var editMode: EditMode = .inactive
#endif

    var body: some View {
        let search = NoteSearch(searchText)
        let sections = NoteListSections(pages: pages, folders: folders, sort: sort)
        let results = search.results(in: pages, sort: sort)
        let hasLiveNotes = pages.contains(where: \.isLive)

        ScrollViewReader { proxy in
        List(selection: $selection) {
            if search.isEmpty {
                homeRow
            }

            if storageIsEphemeral {
                Label(
                    "Storage is unavailable, so changes made now won't be saved.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            if !search.isEmpty {
                resultRows(results, for: search)
            } else if !sections.hasPinned && sections.folders.isEmpty {
                noteRows(sections.unfiled)
            } else {
                if sections.hasPinned {
                    Section("Pinned") {
                        folderRows(sections.pinnedFolders)
                        noteRows(sections.pinnedNotes, showsFolder: true)
                    }
                }

                if !sections.folders.isEmpty {
                    Section("Folders") {
                        folderRows(sections.folders)
                    }
                }

                if !sections.unfiled.isEmpty {
                    Section("Notes") {
                        noteRows(sections.unfiled)
                    }
                }
            }
        }
        .overlay {
            if !search.isEmpty && results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if search.isEmpty && !hasLiveNotes && folders.isEmpty {
                emptyList
            }
        }
        .overlay(alignment: .bottom) {
            if showsToasts, let toasts {
                ToastOverlay(center: toasts, bottomInset: 12)
            }
        }
        .searchable(text: $searchText, prompt: "Search Notes")
        .searchFocused($searchIsFocused)
        .onChange(of: request, initial: true) { _, asked in
            guard let asked else { return }
            request = nil
            answer(asked, scrolling: proxy)
        }
        // A bar at the foot of the list: Recently Deleted, when it holds
        // anything, and the gear.
        // Not a `.bottomBar` toolbar item: in the simulator that placement
        // put the gear at the centre of the screen with the list hidden, and
        // it wasn't there in portrait. An inset on the list stays with it.
        .safeAreaInset(edge: .bottom) {
            HStack {
                let deletedCount = pages.filter { !$0.isLive }.count
                if deletedCount > 0 {
                    Button {
                        showsRecentlyDeleted = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Recently Deleted")
                            Text(deletedCount, format: .number)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recentlyDeletedRow")
                }
                Spacer()
                Button("Settings", systemImage: "gearshape", action: onShowSettings)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .accessibilityIdentifier("settingsButton")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle("NoteCode")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
#endif
        .toolbar {
            // Two items at most, so the sidebar keeps room for its title:
            // with Edit, Sort and New side by side, "NoteCode" didn't show.
            ToolbarItem {
#if os(iOS)
                if editMode.isEditing {
                    Button("Done") {
                        withAnimation { editMode = .inactive }
                    }
                } else {
                    listMenu
                }
#else
                listMenu
#endif
            }
            ToolbarItem {
                // A tap makes a note the way Settings › New Notes says; holding
                // it offers the other orientation and a folder.
                Menu {
                    newNoteButtons(in: newNoteFolder)
                    Divider()
                    templateMenu(in: newNoteFolder)
                    Divider()
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        editingFolder = .new(moving: nil)
                    }
                } label: {
                    Label("New", systemImage: "plus")
                } primaryAction: {
                    addPage(newNoteOrientation, in: newNoteFolder)
                }
                .accessibilityIdentifier("newNoteButton")
            }
        }
#if os(iOS)
        .environment(\.editMode, $editMode)
#endif
        .sheet(item: $infoPage) { page in
            NoteInfoView(page: page)
        }
        .sheet(item: $editingFolder) { editing in
            FolderEditor(editing: editing)
        }
        .sheet(isPresented: $showsRecentlyDeleted) {
            RecentlyDeletedView()
        }
        .alert("Rename Note", isPresented: $showsNameAlert) {
            TextField("Name", text: $typedName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { finishRenamingPage() }
        }
        }
    }

    /// Home, at the top of the list. Not a note, so it is never selected; it
    /// clears the selection instead, and is tinted like a selected row while
    /// Home is what the page shows.
    private var homeRow: some View {
        Button(action: onShowHome) {
            Label {
                Text("Home")
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "house")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .listRowBackground(selection == nil ? RowSelectionTint.color(isDark: colorScheme == .dark) : nil)
        .accessibilityIdentifier("homeRow")
        .accessibilityAddTraits(selection == nil ? .isSelected : [])
    }

    /// Does what the menu bar asked. The list may have only just slid in, and
    /// a field focused or an alert raised in the same frame is dropped, so it
    /// waits for the slide.
    private func answer(_ request: ListRequest, scrolling proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            switch request {
            case .newFolder:   editingFolder = .new(moving: nil)
            case .searchNotes: searchIsFocused = true
            case .showFolder(let id):
                // Opened if the reader had closed it, then brought into view.
                closedFolders.remove(id)
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    // MARK: Empty states

    /// A list with no notes and no folders: the two ways to start.
    ///
    /// "Open Welcome Note" makes a new copy, as Settings does, rather than
    /// looking for one: an empty list means the first launch's copy is gone.
    private var emptyList: some View {
        ContentUnavailableView {
            Label("No Notes", systemImage: "note.text")
        } description: {
            Text("Start a note, or open the tour of what NoteCode does.")
        } actions: {
            Button("New Note") {
                addPage(newNoteOrientation, in: nil)
            }
            .buttonStyle(.borderedProminent)
            Button("Open Welcome Note") {
                selection = WelcomeNote.make(in: modelContext)
            }
        }
    }

    /// What a folder shows when nothing is filed in it. Not a note, so it
    /// can't be selected.
    private var emptyFolderRow: some View {
        Text("No Notes")
            .foregroundStyle(.secondary)
            .selectionDisabled()
    }

    // MARK: Rows

    /// A row's picture of the note's first page: 30 by 39 (the `Library`
    /// board), Letter's proportions.
    private static let thumbnailSize = CGSize(width: 30, height: 39)

    /// - Parameter showsFolder: whether each row names its folder, for the
    ///   Pinned section, where notes from every folder sit together.
    private func noteRows(_ notes: [Page], showsFolder: Bool = false) -> some View {
        ForEach(notes) { page in
            HStack(spacing: 12) {
                NoteThumbnailView(page: page)
                    .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                VStack(alignment: .leading) {
                    Text(page.title)
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
            .tag(page)
            .listRowBackground(rowBackground(for: page))
            .contextMenu { noteMenu(page) }
        }
        .onDelete { offsets in
            deletePages(offsets.map { notes[$0] })
        }
    }

    /// A search's results: each note's title, the line it matched on, and
    /// where it's filed, with the words searched for in bold.
    private func resultRows(_ results: [NoteSearch.Result], for search: NoteSearch) -> some View {
        ForEach(results) { result in
            let page = result.page
            HStack(spacing: 12) {
                NoteThumbnailView(page: page)
                    .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                VStack(alignment: .leading, spacing: 2) {
                    Text(search.highlighted(page.title))
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
            .listRowBackground(rowBackground(for: page))
            .contextMenu { noteMenu(page) }
        }
    }

    /// The selected note's row is the accent at a low strength, with the
    /// label colour kept for its text: never white on solid orange.
    private func rowBackground(for page: Page) -> Color? {
        selection == page ? RowSelectionTint.color(isDark: colorScheme == .dark) : nil
    }

    private func folderRows(_ sections: [NoteListSections.FolderSection]) -> some View {
        ForEach(sections) { section in
            DisclosureGroup(isExpanded: isOpen(section.folder)) {
                if section.notes.isEmpty {
                    emptyFolderRow
                } else {
                    noteRows(section.notes)
                }
            } label: {
                folderRow(section)
            }
        }
    }

    private func folderRow(_ section: NoteListSections.FolderSection) -> some View {
        let folder = section.folder
        return HStack {
            HStack(spacing: 10) {
                FolderBadge(folder: folder)
                Text(folder.name)
                    .fontWeight(.semibold)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Text(section.notes.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .contextMenu { folderMenu(folder) }
        // On the row, not the list: on an iPad the dialog is a popover, and
        // attached to the list it pointed at the middle of the list's edge.
        .confirmationDialog(
            "Delete “\(folder.name)”?",
            isPresented: isDeleting(folder),
            titleVisibility: .visible
        ) {
            let count = folder.livePages.count
            if count == 0 {
                Button("Delete Folder", role: .destructive) {
                    delete(folder, .keepingNotes)
                }
            } else {
                Button("Delete Folder and ^[\(count) Note](inflect: true)", role: .destructive) {
                    delete(folder, .withNotes)
                }
                Button("Delete Folder, Keep Notes") {
                    delete(folder, .keepingNotes)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if !folder.livePages.isEmpty {
                Text("Kept notes move out of the folder, to the top of the list. Deleted notes wait in Recently Deleted for 30 days.")
            }
        }
    }

    // MARK: Menus

    /// Edit and Sort By, in one menu the way Notes and Files have them.
    private var listMenu: some View {
        Menu {
#if os(iOS)
            Button("Edit", systemImage: "pencil") {
                withAnimation { editMode = .active }
            }
#endif
            sortMenu
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    private var sortMenu: some View {
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

    @ViewBuilder
    private func newNoteButtons(in folder: Folder?) -> some View {
        // Which way up a note's pages are is chosen here, once. Changing it
        // later would re-wrap the text at another width and move every line
        // out from under its ink.
        ForEach(PageOrientation.allCases, id: \.self) { orientation in
            Button {
                addPage(orientation, in: folder)
            } label: {
                Label("\(orientation.title) Pages", systemImage: orientation.systemImage)
            }
        }
    }

    /// From Template ›: a note that starts with its headings, in the open
    /// note's folder like the + button's tap.
    private func templateMenu(in folder: Folder?) -> some View {
        Menu {
            ForEach(NoteTemplate.allCases) { template in
                Button {
                    addPage(from: template, in: folder)
                } label: {
                    Label(template.title, systemImage: template.systemImage)
                }
            }
        } label: {
            Label("From Template", systemImage: "doc.badge.plus")
        }
        .accessibilityIdentifier("fromTemplateMenu")
    }

    /// The note's long-press menu is the title menu: the same view, so the
    /// same rows in the same order. The list renames through the name alert,
    /// since it has no title to edit in place, and deletes without asking, as
    /// it always has: the note goes to Recently Deleted, and the toast undoes it.
    private func noteMenu(_ page: Page) -> some View {
        NoteTitleMenu(
            page: page,
            folders: folders,
            onNewFolder: { editingFolder = .new(moving: page) },
            onGetInfo: { infoPage = page },
            onDuplicate: { page.duplicated(in: modelContext) },
            onRename: { startRenaming(page) },
            onDelete: { deletePages([page]) }
        )
    }

    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
        Button(
            folder.isPinned ? "Unpin Folder" : "Pin Folder",
            systemImage: folder.isPinned ? "pin.slash" : "pin"
        ) {
            withAnimation { folder.isPinned.toggle() }
        }
        Menu("New Note", systemImage: "square.and.pencil") {
            newNoteButtons(in: folder)
        }
        Button("Rename…", systemImage: "pencil") {
            editingFolder = .rename(folder)
        }
        Picker(selection: runDestination(of: folder)) {
            Text("Default (\(RunDestinationPreference.resolve([appDefaultDestination]).name))")
                .tag(String?.none)
            ForEach(CodeDestination.builtIns) { destination in
                Text(destination.name).tag(String?.some(destination.id))
            }
            // A custom site set at either level stays in the menu.
            ForEach(customDestinations(for: folder)) { destination in
                Text(destination.name).tag(String?.some(destination.id))
            }
        } label: {
            Label("Run Code Blocks In", systemImage: "play.rectangle")
        }
        .pickerStyle(.menu)
        Divider()
        Button("Delete Folder…", systemImage: "trash", role: .destructive) {
            deleting = folder
        }
    }

    private func customDestinations(for folder: Folder) -> [CodeDestination] {
        [folder.runDestination, appDefaultDestination].compactMap { id -> CodeDestination? in
            guard let id, let destination = CodeDestination(id: id),
                  case .custom = destination else { return nil }
            return destination
        }
        .reduce(into: [CodeDestination]()) { found, destination in
            if !found.contains(destination) { found.append(destination) }
        }
    }

    // MARK: Bindings

    private func isOpen(_ folder: Folder) -> Binding<Bool> {
        Binding {
            !closedFolders.contains(folder.persistentModelID)
        } set: { open in
            if open {
                closedFolders.remove(folder.persistentModelID)
            } else {
                closedFolders.insert(folder.persistentModelID)
            }
        }
    }

    /// Picking a key also picks the way round that reads naturally for it.
    private var sortKey: Binding<NoteSort.Key> {
        Binding { sort.key } set: { sort = sort.with(key: $0) }
    }

    private func runDestination(of folder: Folder) -> Binding<String?> {
        Binding { folder.runDestination } set: { folder.runDestination = $0 }
    }

    private func isDeleting(_ folder: Folder) -> Binding<Bool> {
        Binding { deleting == folder } set: { if !$0 { deleting = nil } }
    }

    // MARK: Changes

    /// Where the "+" button files a new note: with the note that's open, so
    /// a student working through a class's folder keeps adding to it. At the
    /// top of the list when no note is open, or the open one has no folder.
    private var newNoteFolder: Folder? {
        NewNotes.folder(whileViewing: selection)
    }

    private func addPage(_ orientation: PageOrientation, in folder: Folder?) {
        let page: Page = withAnimation {
            if let folder {
                closedFolders.remove(folder.persistentModelID)
            }
            return Page.create(orientation: orientation, in: folder, context: modelContext)
        }
        onNewPage(page)
        selection = page
    }

    private func addPage(from template: NoteTemplate, in folder: Folder?) {
        let page: Page = withAnimation {
            if let folder {
                closedFolders.remove(folder.persistentModelID)
            }
            return Page.create(from: template, orientation: newNoteOrientation, in: folder, context: modelContext)
        }
        onNewPage(page)
        selection = page
    }

    private func startRenaming(_ page: Page) {
        typedName = page.title
        renamingPage = page
        showsNameAlert = true
    }

    private func finishRenamingPage() {
        guard let page = renamingPage else { return }
        // An edit, as renaming from the title is: the date moves.
        page.title = Page.title(fromTyped: typedName)
        page.modifiedAt = .now
    }

    /// Moves notes to Recently Deleted, with a toast that puts them back.
    private func deletePages(_ deleted: [Page]) {
        if let selection, deleted.contains(selection) {
            self.selection = nil
        }
        withAnimation {
            // If saving fails, the change is still pending in the context,
            // and autosave tries again.
            try? Page.moveToRecentlyDeleted(deleted, from: modelContext)
        }
        announceMoved(deleted)
    }

    private func announceMoved(_ moved: [Page]) {
        guard !moved.isEmpty, let toasts else { return }
        let context = modelContext
        toasts.show(
            moved.count == 1 ? "Moved to Recently Deleted" : "Moved \(moved.count) notes to Recently Deleted",
            actionTitle: "Undo"
        ) {
            withAnimation { try? Page.restore(moved, in: context) }
        }
    }

    private func delete(_ folder: Folder, _ deletion: Folder.Deletion) {
        // Only the notes the reader could see go to Recently Deleted; the ones
        // already there keep their first date.
        let going = deletion == .withNotes ? folder.livePages : []
        // The open note closes first if it's going.
        if let selection, going.contains(selection) {
            self.selection = nil
        }
        withAnimation {
            try? Folder.delete(folder, deletion, from: modelContext)
        }
        // The folder is gone for good, so Undo brings the notes back to the
        // top of the list, not into a folder.
        announceMoved(going)
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

    static func color(isDark: Bool) -> Color {
        Color.accentColor.opacity(opacity(isDark: isDark))
    }
}
