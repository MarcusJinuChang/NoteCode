//
//  OpenElsewhereView.swift
//  NoteCode
//

import SwiftUI

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
