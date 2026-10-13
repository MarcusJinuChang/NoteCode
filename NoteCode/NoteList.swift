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

    /// What the menu bar has asked the list to do (New Folder, Search Notes).
    /// Answered when the list is on screen, then cleared.
    @Binding var request: ListRequest?

    init(
        storageIsEphemeral: Bool = false,
        selection: Binding<Page?>,
        searchText: Binding<String>,
        onNewPage: @escaping (Page) -> Void = { _ in },
        onShowSettings: @escaping () -> Void = {},
        request: Binding<ListRequest?> = .constant(nil)
    ) {
        self.storageIsEphemeral = storageIsEphemeral
        _selection = selection
        _searchText = searchText
        self.onNewPage = onNewPage
        self.onShowSettings = onShowSettings
        _request = request
    }

    @FocusState private var searchIsFocused: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
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

    /// What the name alert is naming. Kept after the alert closes, since
    /// its button may run after the alert has said it's gone.
    @State private var naming: FolderNaming?
    @State private var showsNameAlert = false
    @State private var typedName = ""

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

        List(selection: $selection) {
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
            } else if search.isEmpty && pages.isEmpty && folders.isEmpty {
                emptyList
            }
        }
        .searchable(text: $searchText, prompt: "Search Notes")
        .searchFocused($searchIsFocused)
        .onChange(of: request, initial: true) { _, asked in
            guard let asked else { return }
            request = nil
            answer(asked)
        }
        // A bar at the foot of the list that holds only the gear, for now.
        // Not a `.bottomBar` toolbar item: in the simulator that placement
        // put the gear at the centre of the screen with the list hidden, and
        // it wasn't there in portrait. An inset on the list stays with it.
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Settings", systemImage: "gearshape", action: onShowSettings)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .accessibilityIdentifier("settingsButton")
                Spacer()
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
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        startNaming(.new(moving: nil))
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
        .alert(naming?.title ?? "", isPresented: $showsNameAlert) {
            TextField("Name", text: $typedName)
            Button("Cancel", role: .cancel) {}
            Button(naming?.confirmation ?? "OK") { finishNaming() }
        }
    }

    /// Does what the menu bar asked. The list may have only just slid in, and
    /// a field focused or an alert raised in the same frame is dropped, so it
    /// waits for the slide.
    private func answer(_ request: ListRequest) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            switch request {
            case .newFolder:   startNaming(.new(moving: nil))
            case .searchNotes: searchIsFocused = true
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

    /// - Parameter showsFolder: whether each row names its folder, for the
    ///   Pinned section, where notes from every folder sit together.
    private func noteRows(_ notes: [Page], showsFolder: Bool = false) -> some View {
        ForEach(notes) { page in
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
            Label(folder.name, systemImage: "folder")
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
            let count = folder.pages?.count ?? 0
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
            if folder.pages?.isEmpty == false {
                Text("Kept notes move out of the folder, to the top of the list.")
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

    /// The note's long-press menu is the title menu: the same view, so the
    /// same rows in the same order. The list renames through the name alert,
    /// since it has no title to edit in place, and deletes without asking, as
    /// it always has.
    private func noteMenu(_ page: Page) -> some View {
        NoteTitleMenu(
            page: page,
            folders: folders,
            onNewFolder: { startNaming(.new(moving: page)) },
            onGetInfo: { infoPage = page },
            onRename: { startNaming(.renamePage(page)) },
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
            startNaming(.rename(folder))
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

    private func startNaming(_ naming: FolderNaming) {
        switch naming {
        case .rename(let folder):   typedName = folder.name
        case .renamePage(let page): typedName = page.title
        case .new:                  typedName = ""
        }
        self.naming = naming
        showsNameAlert = true
    }

    private func finishNaming() {
        let name = Folder.name(fromTyped: typedName)
        switch naming {
        case .new(let moving):
            let folder = Folder(name: name)
            withAnimation {
                modelContext.insert(folder)
                moving?.folder = folder
            }
        case .rename(let folder):
            folder.name = name
        case .renamePage(let page):
            // An edit, as renaming from the title is: the date moves.
            page.title = Page.title(fromTyped: typedName)
            page.modifiedAt = .now
        case nil:
            break
        }
    }

    private func deletePages(_ deleted: [Page]) {
        if let selection, deleted.contains(selection) {
            self.selection = nil
        }
        withAnimation {
            // If saving fails, the deletion is still pending in the context,
            // and autosave tries again.
            try? Page.delete(deleted, from: modelContext)
        }
    }

    private func delete(_ folder: Folder, _ deletion: Folder.Deletion) {
        // The open note closes first if it's going: a deleted note's ink
        // can't be read once the deletion is saved (see AGENTS.md).
        if deletion == .withNotes, let selection, selection.folder == folder {
            self.selection = nil
        }
        withAnimation {
            try? Folder.delete(folder, deletion, from: modelContext)
        }
    }
}

/// What the name alert is for.
private enum FolderNaming {
    /// A new folder, with the note to move into it when it came from a
    /// note's "Move to Folder" menu.
    case new(moving: Page?)
    case rename(Folder)
    /// A note, renamed from the list's menu.
    case renamePage(Page)

    var title: String {
        switch self {
        case .new:        "New Folder"
        case .rename:     "Rename Folder"
        case .renamePage: "Rename Note"
        }
    }

    var confirmation: String {
        switch self {
        case .new:        "Create"
        case .rename,
             .renamePage: "Rename"
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

    static func color(isDark: Bool) -> Color {
        Color.accentColor.opacity(opacity(isDark: isDark))
    }
}
