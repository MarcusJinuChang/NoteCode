//
//  PageViewMenu.swift
//  NoteCode
//
//  Choosing how pages are shown.
//

import SwiftUI

/// The header's view menu.
///
/// The view mode is a preference about this device and changes nothing in
/// the note. The pages' orientation isn't here: it's chosen when the note is
/// made and fixed from then on — see the new-note menu in `ContentView`.
struct PageViewMenu: View {
    @Binding var mode: PageViewMode

    var body: some View {
        Menu {
            Picker("View", selection: $mode) {
                ForEach(PageViewMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
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
