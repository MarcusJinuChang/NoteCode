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

    init(title: String = "Untitled", content: String = "", drawingData: Data = Data(), createdAt: Date = .now) {
        self.title = title
        self.content = content
        self.drawingData = drawingData
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.runDestination = nil
    }
}
