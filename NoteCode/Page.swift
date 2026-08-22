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

    init(title: String = "Untitled", content: String = "", drawingData: Data = Data(), createdAt: Date = .now) {
        self.title = title
        self.content = content
        self.drawingData = drawingData
        self.createdAt = createdAt
        self.modifiedAt = createdAt
    }
}
