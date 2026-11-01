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
/// own, and are rows among the notes: one list, sorted by the reader's choice,
/// with a Pinned section above it. What goes where, and in what order, is
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

    /// Asked to show Settings, from the list's ••• menu.
    var onShowSettings: () -> Void = {}

    /// What the menu bar has asked the list to do (New Folder, Search Notes).
    /// Answered when the list is on screen, then cleared.
    @Binding var request: ListRequest?

    /// Ask the window for the file picker, and for the Export All sheet.
    var onImport: () -> Void
    var onExportAll: () -> Void

    /// Whether the list is the one to draw the toast: it is when the list is
    /// on screen, and the open note's page draws it when the list is away.
    var showsToasts = true

    init(
        storageIsEphemeral: Bool = false,
        selection: Binding<Page?>,
        searchText: Binding<String>,
        onNewPage: @escaping (Page) -> Void = { _ in },
        onShowSettings: @escaping () -> Void = {},
        onImport: @escaping () -> Void = {},
        onExportAll: @escaping () -> Void = {},
        request: Binding<ListRequest?> = .constant(nil),
        showsToasts: Bool = true
    ) {
        self.storageIsEphemeral = storageIsEphemeral
        _selection = selection
        _searchText = searchText
        self.onNewPage = onNewPage
        self.onShowSettings = onShowSettings
        self.onImport = onImport
        self.onExportAll = onExportAll
        _request = request
        self.showsToasts = showsToasts
    }

    @FocusState private var searchIsFocused: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AccentPalette.defaultsKey) private var accent = ""
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

    /// Whether a note made here is opened (Settings › Notes › Open Note After
    /// Creating).
    @AppStorage(NewNotes.opensAfterCreatingKey)
    private var opensNewNote = NewNotes.opensAfterCreatingByDefault

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

    /// Whether the tip jar's sheet is showing.
    @State private var showsTipJar = false

    /// The app's tip jar, for the list's foot; absent in previews and tests.
    @Environment(TipJar.self) private var tipJar: TipJar?

    /// The folder whose deletion is waiting on the reader's choice.
    @State private var deleting: Folder?

    /// The note whose info is showing.
    @State private var infoPage: Page?

    /// What is being dragged and where it would land.
    @State private var drag = ListDragState()

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
        let deletedCount = pages.filter { !$0.isLive }.count

        ScrollViewReader { proxy in
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
            } else {
                if sections.hasPinned {
                    Section("Pinned") {
                        itemRows(sections.pinnedItems, showsFolder: true)
                    }
                }

                if sections.hasPinned || !sections.folders.isEmpty {
                    // The header is the drop target for the top level: a folder
                    // dropped on it goes to the top, a note out of its folder.
                    Section {
                        itemRows(sections.items)
                    } header: {
                        Text("Library")
                            .modifier(ListRowDrop(target: .topFolders, hoverID: .topFolders, drag: drag, outset: 12))
                    }
                } else {
                    itemRows(sections.items)
                }
            }

            if search.isEmpty, deletedCount > 0 {
                recentlyDeletedRow(count: deletedCount)
            }

            // Not under the empty list's overlay, which would sit on it.
            if search.isEmpty, hasLiveNotes || !folders.live.isEmpty {
                ListFoot(tipJar: tipJar) { showsTipJar = true }
            }
        }
#if canImport(UIKit)
        .background { ListDropBridge(drag: drag, folders: folders, perform: performDrop) }
#endif
        .overlay {
            if !search.isEmpty && results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if search.isEmpty && !hasLiveNotes && folders.live.isEmpty {
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
        .navigationTitle("NoteCode")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
#endif
        .toolbar {
            // Two items at most, so the sidebar keeps room for its title:
            // with Edit, Sort and New side by side, "NoteCode" didn't show.
            // No glass behind either button: they sit on the bar's opaque
            // surface like the buttons of every other bar (`BarMaterial`).
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
            .sharedBackgroundVisibility(.hidden)
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
            .sharedBackgroundVisibility(.hidden)
        }
#if os(iOS)
        .toolbarBackground(BarMaterial.fill, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // The sidebar's own surface is Home's grey, not the system's
        // translucent sidebar material.
        .scrollContentBackground(.hidden)
        .background(HomePalette.background.ignoresSafeArea())
#endif
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
        .sheet(isPresented: $showsTipJar) {
            if let tipJar { TipJarView(jar: tipJar) }
        }
        .alert("Rename Note", isPresented: $showsNameAlert) {
            TextField("Name", text: $typedName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { finishRenamingPage() }
        }
        }
    }

    /// Recently Deleted, the list's last row, while it holds anything. Not a
    /// note, so it is never selected; it raises the sheet.
    private func recentlyDeletedRow(count: Int) -> some View {
        Button {
            showsRecentlyDeleted = true
        } label: {
            Label {
                HStack {
                    Text("Recently Deleted")
                    Spacer()
                    Text(count, format: .number)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "trash")
            }
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .modifier(ListRowDrop(target: .recentlyDeleted, hoverID: .recentlyDeleted, drag: drag))
        .accessibilityIdentifier("recentlyDeletedRow")
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
            Label { Text("No Notes") } icon: { EmptyStateMark() }
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

    /// How far a row is pushed in for each folder above it.
    private func indent(_ depth: Int) -> CGFloat {
        CGFloat(min(depth, 6)) * 18
    }

    /// One note's row, at `depth` folders down. Dragged to file it, and a
    /// drop target itself: dropped on, it files the other note beside it.
    private func noteRow(_ page: Page, depth: Int, showsFolder: Bool) -> some View {
        HStack(spacing: 12) {
            NoteThumbnailView(page: page)
                .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
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
        .padding(.leading, indent(depth))
        .tag(page)
        .opensOnTapInCompactWidth { selection = page }
        .listRowBackground(rowBackground(for: page))
        .contextMenu { noteMenu(page) }
        .onDrag { drag.lift(.note(page)) }
        .modifier(ListRowDrop(
            target: .note(page), hoverID: .row(.note(page.persistentModelID)), drag: drag
        ))
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
            .opensOnTapInCompactWidth { selection = page }
            .listRowBackground(rowBackground(for: page))
            .contextMenu { noteMenu(page) }
        }
    }

    /// The selected note's row is the accent at a low strength, with the
    /// label colour kept for its text: never white on solid orange.
    private func rowBackground(for page: Page) -> Color? {
        selection == page ? RowSelectionTint.color(isDark: colorScheme == .dark, accent: accent) : nil
    }

    /// Folders, the notes beside them and what is open in them, flattened into
    /// rows (`NoteListRow`) so each can be dragged and dropped on.
    ///
    /// - Parameter showsFolder: whether the notes at this level name their
    ///   folder, for the Pinned section, where notes from every folder sit
    ///   together.
    private func itemRows(_ items: [NoteListSections.Item], showsFolder: Bool = false) -> some View {
        let rows = NoteListRow.rows(for: items, closed: closedFolders, showsFolder: showsFolder)
        return ForEach(rows) { row in
            switch row {
            case .folder(let section, let depth, let isOpen):
                folderRow(section, depth: depth, isOpen: isOpen)
            case .note(let page, let depth, let showsFolder):
                noteRow(page, depth: depth, showsFolder: showsFolder)
            case .empty(_, let depth):
                emptyFolderRow
                    .padding(.leading, indent(depth))
                    .deleteDisabled(true)
            }
        }
        .onDelete { offsets in
            deletePages(offsets.compactMap { offset in
                if case .note(let page, _, _) = rows[offset] { page } else { nil }
            })
        }
    }

    /// A folder's row: an arrow on the left that opens and closes it, the
    /// folder's face and name, and how many notes are under it. A tap
    /// anywhere on the row does what the arrow does. Dragged to move or
    /// arrange it; dropped on, its top and bottom edges arrange and its middle
    /// takes what is dropped (`ListDrop`).
    private func folderRow(_ section: NoteListSections.FolderSection, depth: Int, isOpen: Bool) -> some View {
        let folder = section.folder
        return HStack(spacing: 4) {
            Button {
                toggle(folder)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 28, height: 44)
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
        .padding(.leading, indent(depth))
        .contentShape(Rectangle())
        .onTapGesture { toggle(folder) }
        .deleteDisabled(true)
        .onDrag { drag.lift(.folder(folder)) }
        .modifier(ListRowDrop(
            target: .folder(folder), hoverID: .row(.folder(folder.persistentModelID)), drag: drag
        ))
        .contextMenu { folderMenu(folder) }
        // On the row, not the list: on an iPad the dialog is a popover, and
        // attached to the list it pointed at the middle of the list's edge.
        .confirmationDialog(
            "Delete “\(folder.name)”?",
            isPresented: isDeleting(folder),
            titleVisibility: .visible
        ) {
            let count = folder.subtreeLivePageCount
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
            if folder.subtreeLivePageCount > 0 || !(folder.subfolders ?? []).isEmpty {
                Text("Kept notes and folders move up one level, to where this folder is. The folder and what is deleted with it wait in Recently Deleted for 30 days.")
            }
        }
    }

    // MARK: Menus

    /// Edit and Sort By, in one menu the way Notes and Files have them.
    private var listMenu: some View {
        Menu {
#if os(iOS)
            Button("Edit", systemImage: "checkmark.circle") {
                withAnimation { editMode = .active }
            }
#endif
            sortMenu
            Divider()
            Button("Import…", systemImage: "square.and.arrow.down", action: onImport)
            Button("Export All Notes…", systemImage: "square.and.arrow.up", action: onExportAll)
            Divider()
            // The app's, not the list's: ⌘, opens it from anywhere, and Home
            // has a gear of its own.
            Button("Settings", systemImage: "gearshape", action: onShowSettings)
                .accessibilityIdentifier("settingsButton")
        } label: {
            Label("More", systemImage: "ellipsis.circle")
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
        Button("Rename…", systemImage: "pencil") {
            editingFolder = .rename(folder)
        }
        Menu("New", systemImage: "plus") {
            newNoteButtons(in: folder)
            Divider()
            Button("Folder Inside…", systemImage: "folder.badge.plus") {
                closedFolders.remove(folder.persistentModelID)
                editingFolder = .new(moving: nil, in: folder)
            }
        }
        Divider()
        Menu("Move To", systemImage: "folder") {
            Button("Top Level", systemImage: "tray") {
                move(folder, into: nil)
            }
            .disabled(folder.parent == nil)
            ForEach(folders.live.filter { folder.canMove(into: $0) && $0 !== folder.parent }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) { target in
                Button(target.path) { move(folder, into: target) }
            }
        }
        Divider()
        Button("Delete Folder…", systemImage: "trash", role: .destructive) {
            deleting = folder
        }
    }

    // MARK: Bindings

    private func toggle(_ folder: Folder) {
        withAnimation(.snappy) {
            if closedFolders.contains(folder.persistentModelID) {
                closedFolders.remove(folder.persistentModelID)
            } else {
                closedFolders.insert(folder.persistentModelID)
            }
        }
    }

    /// Moves a folder from its menu: to the end of another folder, or the top.
    private func move(_ folder: Folder, into target: Folder?) {
        performDrop(.moveFolder(folder, into: target, at: nil))
    }

    /// Does what a drop or a menu decided. Not an edit: nothing's date
    /// moves. Saved at once, so a move isn't lost to a kill before autosave.
    private func performDrop(_ action: ListDropAction) {
        switch action {
        case .deleteNote(let page):
            deletePages([page])
            return
        case .deleteFolder(let folder):
            delete(folder, .withNotes)
            return
        default:
            break
        }
        withAnimation {
            ListDrop.perform(action, among: folders)
            switch action {
            case .fileNote(_, into: let folder?), .moveFolder(_, into: let folder?, _):
                closedFolders.remove(folder.persistentModelID)
            default:
                break
            }
        }
        try? modelContext.save()
    }

    /// Picking a key also picks the way round that reads naturally for it.
    private var sortKey: Binding<NoteSort.Key> {
        Binding { sort.key } set: { sort = sort.with(key: $0) }
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
        finishAdding(page, in: folder)
    }

    private func addPage(from template: NoteTemplate, in folder: Folder?) {
        let page: Page = withAnimation {
            if let folder {
                closedFolders.remove(folder.persistentModelID)
            }
            return Page.create(from: template, orientation: newNoteOrientation, in: folder, context: modelContext)
        }
        finishAdding(page, in: folder)
    }

    /// Opens a note just made, or, with Open Note After Creating off, leaves
    /// the reader where they were and says it was added, with a way in.
    private func finishAdding(_ page: Page, in folder: Folder?) {
        if opensNewNote {
            onNewPage(page)
        } else {
            toasts?.show(NewNotes.addedMessage(in: folder), actionTitle: "Open") {
                onNewPage(page)
                selection = page
            }
        }
        selection = NewNotes.selection(afterCreating: page, current: selection, opens: opensNewNote)
    }

    private func startRenaming(_ page: Page) {
        typedName = page.displayTitle
        renamingPage = page
        showsNameAlert = true
    }

    private func finishRenamingPage() {
        guard let page = renamingPage else { return }
        // An edit, as renaming from the title is: the date moves.
        page.rename(to: typedName)
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
        // Kept notes leave a folder that is gone for good, so there is nothing
        // to undo. Deleted ones went with the folder, and Undo brings both back.
        guard deletion == .withNotes, let toasts else { return }
        let context = modelContext
        toasts.show("Moved “\(folder.name)” to Recently Deleted", actionTitle: "Undo") {
            withAnimation { try? Folder.restore([folder], in: context) }
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

    /// - Parameter accent: the stored accent (`AccentPalette.defaultsKey`).
    static func color(isDark: Bool, accent: String) -> Color {
        Color.accent(stored: accent).opacity(opacity(isDark: isDark))
    }
}
