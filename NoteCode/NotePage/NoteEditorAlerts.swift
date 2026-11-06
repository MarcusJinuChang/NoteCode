//
//  NoteEditorAlerts.swift
//  NoteCode
//
//  The two prompts the editor raises on the note: Custom… in the size
//  control's list, and the Link address. They were `@State` and modifiers
//  in `PageDetailView`.
//

#if canImport(UIKit)
import SwiftUI

struct NoteEditorAlerts: ViewModifier {
    let editor: NoteEditor

    /// What Custom… has typed so far.
    @State private var customSize = ""
    /// What the Link alert's field holds.
    @State private var linkAddress = ""

    func body(content: Content) -> some View {
        content
            // Custom… in the size control's list.
            .alert("Text Size", isPresented: Binding(
                get: { editor.customSizeSelection != nil },
                set: { _ in }
            )) {
                TextField("Points", text: $customSize)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { editor.cancelCustomSize() }
                Button("Set") { editor.finishCustomSize(typed: customSize) }
            } message: {
                Text("8 to 72 points.")
            }
            .onChange(of: editor.customSizeSelection != nil) { _, asking in
                if asking { customSize = editor.selectionTextSize.points.map(SpanSize.label(points:)) ?? "" }
            }
            .alert("Add Link", isPresented: Binding(
                get: { editor.linkTarget != nil },
                set: { _ in }
            )) {
                TextField("Address", text: $linkAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { editor.cancelLink() }
                Button("Add") { editor.finishLink(address: linkAddress) }
            } message: {
                Text("Where the link goes.")
            }
            .onChange(of: editor.linkTarget != nil) { _, asking in
                if asking { linkAddress = "" }
            }
    }
}
#endif
