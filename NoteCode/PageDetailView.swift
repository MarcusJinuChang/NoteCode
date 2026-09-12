//
//  PageDetailView.swift
//  NoteCode
//

import SwiftUI

// The iOS editor is DocumentTextView (TextKit 2). Fence detection lands on
// top of it next; macOS keeps the plain TextEditor for now.
struct PageDetailView: View {
    @Bindable var page: Page

    /// Where code blocks run when a page hasn't chosen for itself. Not in the
    /// model: it is a preference about this device, not a property of a note,
    /// and it has to have a value before any page exists.
    @AppStorage(RunDestinationPreference.appDefaultKey)
    private var appDefaultDestination: String = CodeDestination.default.id

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $page.title)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .padding()

            Divider()

#if canImport(UIKit)
            DocumentTextView(
                text: $page.content,
                runDestination: RunDestinationPreference.resolve(
                    [page.runDestination, appDefaultDestination]
                )
            )
#else
            TextEditor(text: $page.content)
                .font(.body)
                .padding(.horizontal, 8)
#endif
        }
        .toolbar {
            RunDestinationMenu(
                pageSetting: $page.runDestination,
                appDefault: $appDefaultDestination
            )
        }
        .onChange(of: page.title) { page.modifiedAt = .now }
        .onChange(of: page.content) { page.modifiedAt = .now }
    }
}
