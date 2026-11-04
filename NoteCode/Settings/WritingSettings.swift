//
//  WritingSettings.swift
//  NoteCode
//
//  Settings › Writing (split out of SettingsView.swift).
//

import SwiftUI

struct WritingSettings: View {
    @AppStorage(ShowMarkdown.defaultsKey) private var showMarkdown = ShowMarkdown.whileEditing
    @AppStorage(TextRewritingPolicy.proseDefaultsKey)
    private var rewritesProse = TextRewritingPolicy.proseEnabledByDefault
    @AppStorage(MarkerDimming.headingsKey) private var headingMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.bulletsKey) private var bulletMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.checkboxesKey) private var checkboxMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.fencesKey) private var fenceMarkers = MarkerLevel.dim
    @AppStorage(AIFeatureSettings.enabledKey) private var aiEnabled = true
    @AppStorage(AIFeatureSettings.lengthKey) private var aiLength = AIAnswerLength.standard.rawValue
    @AppStorage(AIFeatureSettings.insertStyleKey) private var aiInsertStyle = AIInsertStyle.quote.rawValue

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

            assistantSection
        }
        .navigationTitle("Writing")
    }

    /// Explain Code and Summarise Note, on Apple's on-device model.
    private var assistantSection: some View {
        Section {
            Toggle("Assistant", isOn: $aiEnabled)
            Picker("Answer Length", selection: $aiLength) {
                ForEach(AIAnswerLength.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Insert As", selection: $aiInsertStyle) {
                ForEach(AIInsertStyle.allCases) { Text($0.title).tag($0.rawValue) }
            }
        } header: {
            Text("On-Device Assistant")
        } footer: {
            Text(assistantFooter)
        }
    }

    private var assistantFooter: String {
        let base = "Explain a code block and summarise a note with Apple Intelligence. It runs on this \(AppInfo.deviceName): nothing is sent anywhere and nothing is kept."
        if case .unavailable(let reason) = AIAssistant.systemClient.availability {
            return base + " " + reason.message
        }
        return base
    }
}

extension WritingSettings {
    fileprivate func markerPicker(_ title: String, selection: Binding<MarkerLevel>) -> some View {
        Picker(title, selection: selection) {
            ForEach(MarkerLevel.allCases, id: \.self) { Text($0.title) }
        }
    }
}
