//
//  PageViewMenu.swift
//  NoteCode
//
//  Choosing how pages are shown, and which way up this note's pages are.
//

import SwiftUI

/// The header's view menu.
///
/// Two settings with different owners, in one place because they're both
/// about the page. The view mode is a preference about this device and
/// changes nothing in the note. The orientation belongs to the note, and
/// changing it re-wraps the text.
struct PageViewMenu: View {
    @Binding var mode: PageViewMode
    @Binding var orientation: PageOrientation

    var body: some View {
        Menu {
            Picker("View", selection: $mode) {
                ForEach(PageViewMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }

            Section("This Note's Pages") {
                Picker("Pages", selection: $orientation) {
                    ForEach(PageOrientation.allCases, id: \.self) { orientation in
                        Label(orientation.title, systemImage: orientation.systemImage).tag(orientation)
                    }
                }
            }
        } label: {
            Label("View", systemImage: mode.systemImage)
        }
    }
}

extension PageViewMode {
    var title: String {
        switch self {
        case .seamless:   "Seamless"
        case .compressed: "Compressed"
        case .print:      "Print Layout"
        }
    }

    var systemImage: String {
        switch self {
        case .seamless:   "scroll"
        case .compressed: "rectangle.split.1x2"
        case .print:      "doc.on.doc"
        }
    }
}

extension PageOrientation {
    var title: String {
        switch self {
        case .portrait:  "Portrait"
        case .landscape: "Landscape"
        }
    }

    var systemImage: String {
        switch self {
        case .portrait:  "rectangle.portrait"
        case .landscape: "rectangle"
        }
    }
}
