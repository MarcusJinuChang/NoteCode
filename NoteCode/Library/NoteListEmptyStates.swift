//
//  NoteListEmptyStates.swift
//  NoteCode
//
//  What the note list shows when it, or a folder in it, holds no notes.
//  Moved out of NoteList.swift (D3).
//

import SwiftUI

extension NoteList {
    /// A list with no notes and no folders: the two ways to start.
    ///
    /// "Open Welcome Note" makes a new copy, as Settings does, rather than
    /// looking for one: an empty list means the first launch's copy is gone.
    var emptyList: some View {
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
                selection = WelcomeNote.make(in: modelContext, runLines: extensions.runLines)
            }
        }
    }

    /// What a folder shows when nothing is filed in it. Not a note, so it
    /// can't be selected.
    var emptyFolderRow: some View {
        Text("No Notes")
            .foregroundStyle(.secondary)
            .selectionDisabled()
    }
}
