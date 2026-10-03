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
/// the navigation there is.
struct NoteList: View {
    /// True when the on-disk store failed and edits live only in memory.
    var storageIsEphemeral = false

    @Binding var selection: Page?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Page.modifiedAt, order: .reverse) private var pages: [Page]
    @Query private var folders: [Folder]

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

    var body: some View {
        let sections = NoteListSections(pages: pages, folders: folders)

        List(selection: $selection) {
            if storageIsEphemeral {
                Label(
                    "Storage is unavailable, so changes made now won't be saved.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            if sections.folders.isEmpty {
                noteRows(sections.unfiled)
            } else {
                Section("Folders") {
                    ForEach(sections.folders) { section in
                        DisclosureGroup(isExpanded: isOpen(section.folder)) {
                            noteRows(section.notes)
                        } label: {
                            folderRow(section)
                        }
                    }
                }

                if !sections.unfiled.isEmpty {
                    Section("Notes") {
                        noteRows(sections.unfiled)
                    }
                }
            }
        }
        .navigationTitle("NoteCode")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
#endif
            ToolbarItem {
                Menu {
                    newNoteButtons(in: nil)
                    Divider()
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        startNaming(.new(moving: nil))
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
        .alert(naming?.title ?? "", isPresented: $showsNameAlert) {
            TextField("Name", text: $typedName)
            Button("Cancel", role: .cancel) {}
            Button(naming?.confirmation ?? "OK") { finishNaming() }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: isDeleting,
            titleVisibility: .visible,
            presenting: deleting
        ) { folder in
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
        } message: { folder in
            if folder.pages?.isEmpty == false {
                Text("Kept notes move out of the folder, to the top of the list.")
            }
        }
    }

    // MARK: Rows

    private func noteRows(_ notes: [Page]) -> some View {
        ForEach(notes) { page in
            VStack(alignment: .leading) {
                Text(page.title)
                    .font(.headline)
                Text(page.modifiedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(page)
            .contextMenu { noteMenu(page) }
        }
        .onDelete { offsets in
            deletePages(offsets.map { notes[$0] })
        }
    }

    private func folderRow(_ section: NoteListSections.FolderSection) -> some View {
        HStack {
            Label(section.folder.name, systemImage: "folder")
            Spacer()
            Text(section.notes.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .contextMenu { folderMenu(section.folder) }
    }

    // MARK: Menus

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

    @ViewBuilder
    private func noteMenu(_ page: Page) -> some View {
        Menu("Move to Folder", systemImage: "folder") {
            ForEach(NoteListSections(pages: [], folders: folders).folders) { section in
                Button(section.folder.name) {
                    move(page, to: section.folder)
                }
                .disabled(page.folder == section.folder)
            }
            Divider()
            Button("New Folder…", systemImage: "folder.badge.plus") {
                startNaming(.new(moving: page))
            }
        }
        if page.folder != nil {
            Button("Remove from Folder", systemImage: "folder.badge.minus") {
                move(page, to: nil)
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            deletePages([page])
        }
    }

    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
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
        [folder.runDestination, appDefaultDestination].compactMap { id in
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

    private func runDestination(of folder: Folder) -> Binding<String?> {
        Binding { folder.runDestination } set: { folder.runDestination = $0 }
    }

    private var isDeleting: Binding<Bool> {
        Binding { deleting != nil } set: { if !$0 { deleting = nil } }
    }

    // MARK: Changes

    private func addPage(_ orientation: PageOrientation, in folder: Folder?) {
        let page = Page()
        page.orientation = orientation
        withAnimation {
            modelContext.insert(page)
            page.folder = folder
            if let folder {
                closedFolders.remove(folder.persistentModelID)
            }
        }
        selection = page
    }

    /// Files a note in a folder, or takes it out of one with `nil`.
    ///
    /// Not an edit to the note, so its date modified stays: moving a week of
    /// notes into a folder shouldn't make them all look written today.
    private func move(_ page: Page, to folder: Folder?) {
        withAnimation {
            page.folder = folder
        }
    }

    private func startNaming(_ naming: FolderNaming) {
        if case .rename(let folder) = naming {
            typedName = folder.name
        } else {
            typedName = ""
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

    var title: String {
        switch self {
        case .new:    "New Folder"
        case .rename: "Rename Folder"
        }
    }

    var confirmation: String {
        switch self {
        case .new:    "Create"
        case .rename: "Rename"
        }
    }
}
