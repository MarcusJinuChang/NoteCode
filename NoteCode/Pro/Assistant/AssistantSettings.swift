//
//  AssistantSettings.swift
//  NoteCode
//
//  Settings › Writing › On-Device Assistant, which the App Store edition
//  puts at the end of Writing's form (`AppExtensions.settingsSections`).
//

import SwiftUI

/// Explain Code and Summarise Note, on Apple's on-device model.
struct AssistantSettingsSection: View {
    @AppStorage(SettingKeys.Assistant.enabled.name) private var aiEnabled = true
    @AppStorage(SettingKeys.Assistant.answerLength.name) private var aiLength = AIAnswerLength.standard.rawValue
    @AppStorage(SettingKeys.Assistant.insertStyle.name) private var aiInsertStyle = AIInsertStyle.quote.rawValue

    var body: some View {
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
            Text(footer)
        }
    }

    private var footer: String {
        let base = "Explain a code block and summarise a note with Apple Intelligence. It runs on this \(AppInfo.deviceName): nothing is sent anywhere and nothing is kept."
        if case .unavailable(let reason) = AIAssistant.systemClient.availability {
            return base + " " + reason.message
        }
        return base
    }
}
