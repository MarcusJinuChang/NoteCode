//
//  SettingsView.swift
//  NoteCode
//
//  Settings: a form sheet with a list of sections, each opening a page of its
//  own. Every row reads and writes the key the rest of the app already uses,
//  through the type that owns it (`SettingKeys.General.hotbarDock.name`,
//  `SettingKeys.Notes.sort.name`, …), so there is no second copy of a preference to
//  drift from the first. A row appears only when it does something.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Opening it

extension FocusedValues {
    /// Whether the window in front is showing Settings, so ⌘, can open it.
    @Entry var showsSettings: Binding<Bool>?
}

extension EnvironmentValues {
    /// Whether the window Settings came from can move its hotbar: not in a
    /// compact width, where the bar stays at the bottom. The sheet's own size
    /// class isn't the window's, so the window says.
    @Entry var hotbarCanMove = true
}

extension View {
    /// Presents Settings as a form sheet, and lets ⌘, open it.
    ///
    /// - Parameter onOpenWelcomeNote: called when Help and About › Welcome
    ///   Note is chosen, after the sheet has been asked to close. The note is
    ///   opened by the window, which owns what's selected.
    /// - Parameter onShowWelcomeScreen: called when Help and About › Welcome
    ///   Screen is chosen, likewise after the sheet has been asked to close.
    /// - Parameter onExportFinished: called with the number of notes when
    ///   Notes › Export All Notes… has written them, likewise after the
    ///   sheet has been asked to close, so the window's toast isn't hidden by it.
    /// - Parameter hotbarCanMove: false in a compact width, where General
    ///   leaves out Toolbar Position and Haptic on Snap.
    func settingsSheet(
        isPresented: Binding<Bool>,
        onOpenWelcomeNote: @escaping () -> Void = {},
        onShowWelcomeScreen: @escaping () -> Void = {},
        onExportFinished: @escaping (Int) -> Void = { _ in },
        hotbarCanMove: Bool = true
    ) -> some View {
        self
            .focusedSceneValue(\.showsSettings, isPresented)
            .sheet(isPresented: isPresented) {
                SettingsView(
                    onOpenWelcomeNote: onOpenWelcomeNote,
                    onShowWelcomeScreen: onShowWelcomeScreen,
                    onExportFinished: onExportFinished
                )
                    .presentationSizing(.form)
                    .environment(\.hotbarCanMove, hotbarCanMove)
            }
    }
}

// MARK: - The list of sections

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appExtensions) private var extensions

    /// Makes the Welcome note and opens it. Settings dismisses itself first.
    var onOpenWelcomeNote: () -> Void = {}

    /// Shows the title screen again. Settings dismisses itself first.
    var onShowWelcomeScreen: () -> Void = {}

    /// Told how many notes Export All wrote. Settings dismisses itself first.
    var onExportFinished: (Int) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    GeneralSettings()
                } label: {
                    Label("General", systemImage: "gearshape")
                }
                // The edition's rows (the App Store's: Pro).
                ForEach(extensions.settings(at: .afterGeneral)) { $0.view }
                NavigationLink {
                    NotesSettings(onExportFinished: { count in
                        dismiss()
                        onExportFinished(count)
                    })
                } label: {
                    Label("Notes", systemImage: "note.text")
                }
                NavigationLink {
                    WritingSettings()
                } label: {
                    Label("Writing", systemImage: "textformat")
                }
                NavigationLink {
                    CodeSettings()
                } label: {
                    Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
#if canImport(UIKit)
                NavigationLink {
                    DrawingSettings()
                } label: {
                    Label("Drawing", systemImage: "pencil.tip")
                }
#endif
                NavigationLink {
                    AboutSettings(
                        onOpenWelcomeNote: {
                            dismiss()
                            onOpenWelcomeNote()
                        },
                        onShowWelcomeScreen: {
                            dismiss()
                            onShowWelcomeScreen()
                        }
                    )
                } label: {
                    Label("Help and About", systemImage: "questionmark.circle")
                }
            }
            .navigationTitle("Settings")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
