//
//  PageDetailView.swift
//  NoteCode
//

import SwiftUI

// Placeholder editor — Phase 1 replaces the TextEditor below with a
// TextKit 2 (NSTextLayoutManager) view that detects code fences.
struct PageDetailView: View {
    @Bindable var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $page.title)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .padding()

            Divider()

            TextEditor(text: $page.content)
                .font(.body.monospaced())
                .padding(.horizontal, 8)
        }
        .onChange(of: page.title) { page.modifiedAt = .now }
        .onChange(of: page.content) { page.modifiedAt = .now }
    }
}
