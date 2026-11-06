//
//  NotesSettings.swift
//  NoteCode
//
//  Settings › Notes (split out of SettingsView.swift).
//

import SwiftUI

struct NotesSettings: View {
    var onExportFinished: (Int) -> Void

    @AppStorage(SettingKeys.Notes.newNoteOrientation) private var newNotes
    @AppStorage(SettingKeys.Notes.opensAfterCreating) private var opensAfterCreating
    @AppStorage(SettingKeys.Notes.viewMode) private var viewMode
    @AppStorage(SettingKeys.Notes.sort) private var sort

    var body: some View {
        Form {
            Section {
                Picker("New Notes", selection: $newNotes) {
                    ForEach(PageOrientation.allCases, id: \.self) { Text($0.title) }
                }
                Toggle("Open Note After Creating", isOn: $opensAfterCreating)
            } footer: {
                Text("Which way up the + button's tap makes a note's pages. Hold + to choose the other for one note. A note keeps its orientation once it's made. With Open Note After Creating off, a new note is added to the list and a message offers to open it.")
            }

            Section {
                Picker("View", selection: $viewMode) {
                    ForEach(PageViewMode.allCases, id: \.self) { Text($0.title) }
                }
            } footer: {
                Text("This device's default. ••• › View changes it while a note is open.")
            }

            Section {
                Picker("Sort By", selection: sortKey) {
                    ForEach(NoteSort.Key.allCases, id: \.self) { Text($0.title) }
                }
                Picker("Order", selection: $sort.ascending) {
                    Text(sort.orderTitles.descending).tag(false)
                    Text(sort.orderTitles.ascending).tag(true)
                }
            }

            Section {
                NavigationLink("Recently Deleted") {
                    RecentlyDeletedPage(showsDone: false)
                }
                .accessibilityIdentifier("settingsRecentlyDeleted")
            } footer: {
                Text("Deleted notes wait here for 30 days before they go for good.")
            }

            Section {
                NavigationLink("Export All Notes…") {
                    ExportAllView(onFinished: onExportFinished)
                }
            } footer: {
                Text("Every note as a Markdown file, in a folder for each of yours, to keep or move to another app.")
            }
        }
        .navigationTitle("Notes")
    }

    /// Picking a key picks the way round that reads naturally, as the list's
    /// own menu does: newest first for dates, A to Z for titles.
    private var sortKey: Binding<NoteSort.Key> {
        Binding {
            sort.key
        } set: { key in
            if key != sort.key { sort = sort.with(key: key) }
        }
    }
}
