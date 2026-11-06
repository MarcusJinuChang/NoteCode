//
//  NoteMoreMenu.swift
//  NoteCode
//
//  •••: how pages are shown, the note's text size, the outline and find.
//  About this note only; the app's settings are the list's and Home's.
//

import SwiftUI

struct NoteMoreMenu: View {
    let page: Page
    let onShowSettings: (() -> Void)?
#if canImport(UIKit)
    let editor: NoteEditor
    let viewMode: Binding<PageViewMode>
    /// The header's outline popover (also ⌃⌘O).
    @Binding var showsOutline: Bool
#endif

    var body: some View {
        Menu {
#if canImport(UIKit)
            Section("View") {
                Picker("View", selection: viewMode) {
                    ForEach(PageViewMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }

            // Seamless adds its own pages as ink reaches the end.
            if viewMode.wrappedValue != .seamless {
                Button("Add Page", systemImage: "plus.rectangle.on.rectangle") {
                    editor.addPage()
                }
            }

            // The note's own size, which every size in it is against. The
            // size control in the text row is the selection's.
            Menu {
                Picker("Text Size", selection: Binding(
                    get: { editor.textSize },
                    set: { editor.setTextSize($0) }
                )) {
                    ForEach(NoteTypography.sizes.reversed(), id: \.self) { size in
                        Text(size == NoteTypography.defaultSize ? "\(size) · Default" : "\(size)").tag(size)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Text Size", systemImage: "textformat.size")
            }
            .disabled(editor.mode != .text || page.isTextLocked)

            Button("Outline", systemImage: "list.bullet.indent") { showsOutline = true }

            Button("Find in Note", systemImage: "magnifyingglass") {
                editor.showFind()
            }
            // The text view answers ⌘F itself while it's typing; this is the
            // same shortcut for when it isn't, and listed in the ⌘ overlay.
            .keyboardShortcut(.find)

            // What the edition adds (`EditorFeature`): Summarise Note.
            ForEach(editor.actions(for: .note(title: page.displayTitle), in: .noteMenu)) { action in
                Button(action.title, systemImage: action.symbol) { action.perform() }
                    .disabled(!action.isAvailable)
            }
#endif

            if let onShowSettings {
                Divider()
                Button("Settings", systemImage: "gearshape", action: onShowSettings)
                    .accessibilityIdentifier("noteMenuSettings")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("noteMenu")
#if canImport(UIKit)
        // A popover off the ••• button, since one hung off a menu's items goes
        // when an item is chosen. ⌃⌘O raises the same binding.
        .popover(isPresented: $showsOutline) {
            let outline = editor.outline()
            NoteOutlineView(entries: outline.entries, current: outline.current) { entry in
                showsOutline = false
                editor.scroll(toHeading: entry)
            }
        }
#endif
    }
}
