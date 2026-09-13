//
//  Page.swift
//  NoteCode
//

import Foundation
import SwiftData

@Model
final class Page {
    var title: String
    var content: String
    var drawingData: Data
    var createdAt: Date
    var modifiedAt: Date

    /// Which online compiler this page's run buttons open — a
    /// `CodeDestination.id`, or `nil` to follow the app-wide default.
    ///
    /// Optional so that existing pages migrate without a mapping, and because
    /// "not set" is a real state: a page that never chooses should follow the
    /// default as it changes rather than freeze whatever it was on the day the
    /// page was written. A folder's setting slots in between the two when
    /// folders exist — see `RunDestinationPreference`.
    var runDestination: String?

    /// Which way up this note's pages are — a `PageOrientation` raw value, or
    /// `nil` for a note that has never chosen, which is portrait.
    ///
    /// Stored as a string, like `runDestination`, so existing notes migrate
    /// without a mapping. Unlike that setting, a note keeps whatever it is
    /// given rather than following a default: orientation sets where lines
    /// wrap, and a default that changed would re-wrap every note that had
    /// never chosen.
    var pageOrientation: String?

    init(title: String = "Untitled", content: String = "", drawingData: Data = Data(), createdAt: Date = .now) {
        self.title = title
        self.content = content
        self.drawingData = drawingData
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.runDestination = nil
        self.pageOrientation = nil
    }
}

extension Page {
    var orientation: PageOrientation {
        get { pageOrientation.flatMap(PageOrientation.init(rawValue:)) ?? .default }
        set { pageOrientation = newValue.rawValue }
    }
}
