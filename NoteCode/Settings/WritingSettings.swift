//
//  WritingSettings.swift
//  NoteCode
//
//  Settings › Writing (split out of SettingsView.swift).
//

import SwiftUI

struct WritingSettings: View {
    @AppStorage(SettingKeys.Writing.showMarkdown) private var showMarkdown
    @AppStorage(SettingKeys.Writing.autocorrectInProse) private var rewritesProse
    @AppStorage(SettingKeys.Writing.headingMarkers) private var headingMarkers
    @AppStorage(SettingKeys.Writing.bulletMarkers) private var bulletMarkers
    @AppStorage(SettingKeys.Writing.checkboxMarkers) private var checkboxMarkers
    @AppStorage(SettingKeys.Writing.fenceMarkers) private var fenceMarkers
    @Environment(\.appExtensions) private var extensions

    var body: some View {
        Form {
            Section {
                Picker("Show Markdown", selection: $showMarkdown) {
                    ForEach(ShowMarkdown.allCases, id: \.self) { Text($0.title) }
                }
            } footer: {
                Text("Hashes and backticks show only on the heading or code block you're editing; Always shows them everywhere. Bold, italic, code and link marks stay hidden either way, and the toolbar shows which are on.")
            }

            Section {
                Toggle("Autocorrect", isOn: $rewritesProse)
            } footer: {
                Text("Autocorrect, automatic capitals, smart quotes and dashes and inline predictions while you type text. Turn it off to type exactly what you press. Always off inside code, whichever way this is set.")
            }

            Section {
                markerPicker("Heading Marks", selection: $headingMarkers)
                markerPicker("List Bullets", selection: $bulletMarkers)
                markerPicker("Checkboxes", selection: $checkboxMarkers)
                markerPicker("Code Fences", selection: $fenceMarkers)
            } header: {
                Text("Markers")
            } footer: {
                Text("How the marks that stay visible look: Dim is the quiet grey they have always had, Full is the text's own colour, and Off hides them without moving any line. Heading marks are the hashes shown beside the heading you're editing; List Bullets covers numbers too; a ticked checkbox always shows. These are for this device.")
            }

            // The edition's sections (the App Store's: the on-device assistant).
            ForEach(extensions.settings(at: .writing)) { $0.view }
        }
        .navigationTitle("Writing")
    }
}

extension WritingSettings {
    fileprivate func markerPicker(_ title: String, selection: Binding<MarkerLevel>) -> some View {
        Picker(title, selection: selection) {
            ForEach(MarkerLevel.allCases, id: \.self) { Text($0.title) }
        }
    }
}
