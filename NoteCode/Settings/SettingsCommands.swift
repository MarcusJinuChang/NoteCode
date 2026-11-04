//
//  SettingsCommands.swift
//  NoteCode
//
//  Settings: the ⌘, command (split out of SettingsView.swift).
//

import SwiftUI

/// The ⌘, in the app's menu. A command can't see a window's state, so the
/// window in front hands it the binding (`settingsSheet`).
struct SettingsCommands: Commands {
    @FocusedValue(\.showsSettings) private var showsSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                showsSettings?.wrappedValue = true
            }
            .keyboardShortcut(.settings)
            .disabled(showsSettings == nil)
        }
    }
}
