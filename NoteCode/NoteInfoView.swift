//
//  NoteInfoView.swift
//  NoteCode
//

import SwiftUI

/// A note's info: when it was made and last changed, its folder and pages,
/// and what it holds. Opened from the note's menu in the list, or from the
/// open note's header.
struct NoteInfoView: View {
    let page: Page

    /// How many pages the note runs to, when it's open. `nil` from the list:
    /// a note's pages are known only once it's laid out, and laying out a
    /// closed note to count them would be the cost of opening it.
    var pageCount: Int? = nil

    @Environment(\.dismiss) private var dismiss

    private static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)

    var body: some View {
        let info = NoteInfo(content: page.content)

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Created", value: page.createdAt, format: Self.dateStyle)
                    LabeledContent("Modified", value: page.modifiedAt, format: Self.dateStyle)
                    if let folder = page.folder {
                        LabeledContent("Folder", value: folder.name)
                    }
                }

                Section {
                    LabeledContent("Orientation", value: page.orientation.title)
                    if let pageCount {
                        LabeledContent("Pages", value: pageCount, format: .number)
                    }
                }

                Section("Contents") {
                    LabeledContent("Words", value: info.words, format: .number)
                    LabeledContent("Code Blocks", value: info.codeBlocks, format: .number)
                    ForEach(info.code) { code in
                        LabeledContent(code.name) {
                            Text("^[\(code.blocks) block](inflect: true), ^[\(code.lines) line](inflect: true)")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(page.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 320, minHeight: 380)
#endif
    }
}
