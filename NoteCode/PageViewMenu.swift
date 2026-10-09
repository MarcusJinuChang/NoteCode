//
//  PageViewMenu.swift
//  NoteCode
//
//  The names and icons of how pages are shown and which way up they are.
//
//  The menu that picks the view mode is the View section of the header's •••
//  menu (`PageDetailView`). The mode is a preference about this device and
//  changes nothing in the note. The pages' orientation isn't offered there:
//  it's chosen when the note is made and fixed from then on — see the
//  new-note menu in `NoteList`.
//

import SwiftUI

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
