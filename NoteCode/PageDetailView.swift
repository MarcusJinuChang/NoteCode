//
//  PageDetailView.swift
//  NoteCode
//

import SwiftUI

// The iOS editor is DocumentTextView (TextKit 2). Fence detection lands on
// top of it next; macOS keeps the plain TextEditor for now.
struct PageDetailView: View {
    @Bindable var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $page.title)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .padding()

            Divider()

#if canImport(UIKit)
            DocumentTextView(text: $page.content)
#else
            TextEditor(text: $page.content)
                .font(.body)
                .padding(.horizontal, 8)
#endif
        }
        .onChange(of: page.title) { page.modifiedAt = .now }
        .onChange(of: page.content) { page.modifiedAt = .now }
    }
}
