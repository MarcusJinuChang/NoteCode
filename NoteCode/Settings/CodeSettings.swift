//
//  CodeSettings.swift
//  NoteCode
//
//  Settings › Code (split out of SettingsView.swift).
//

import SwiftUI

struct CodeSettings: View {
    @AppStorage(SettingKeys.Code.codeKeys) private var codeKeys
    @AppStorage(SettingKeys.Code.indentWidth) private var indentWidth
    @AppStorage(SettingKeys.Code.lineNumbers) private var lineNumbers

    var body: some View {
        Form {
            Section {
                Toggle("Code Keys", isOn: $codeKeys)
                // The picker shows whatever is stored, so a value it can't
                // have made is read as 4 here as it is by the editor.
                Picker("Indent Width", selection: Binding(
                    get: { CodeIndent.validWidth(indentWidth) },
                    set: { indentWidth = $0 }
                )) {
                    ForEach(CodeIndent.widths, id: \.self) { Text("\($0) Spaces").tag($0) }
                }
            } footer: {
                Text("Code Keys adds a row of brackets, punctuation, indent and arrow keys above the keyboard while you type code. It isn't shown with a hardware keyboard. Return keeps a line's indent, and goes a level deeper after { ( [ or a Python colon.")
            }

            Section {
                Toggle("Line Numbers", isOn: $lineNumbers)
            } footer: {
                Text("Numbers each line of a code block in the page's margin. They print too, and turning them on moves nothing on the page.")
            }
        }
        .navigationTitle("Code")
    }
}
