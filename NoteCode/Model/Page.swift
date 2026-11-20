//
//  Page.swift
//  NoteCode
//

import Foundation
import SwiftData

extension NoteSchemaV1 {

    @Model
    final class Page {
        var title: String = "Untitled"
        var content: String = ""

        /// The note's ink as `PaperMarkup` bytes, in print layout's coordinates;
        /// empty for a note never drawn on. Read and written through
        /// `DrawingCodec` and `DrawingSaveScheduler`.
        ///
        /// Kept outside the store's own records: 1,000 strokes come to 1.1MB, and
        /// the note list would otherwise load each note's ink along with its
        /// title.
        @Attribute(.externalStorage) var drawingData: Data = Data()
        var createdAt: Date = Date.now
        var modifiedAt: Date = Date.now

        /// Unused since 30 Oct, when the choice of where code runs went: our
        /// run service runs every block. It held a site's id. Kept so version
        /// 1's hashes stay as they are (docs/design/the-model.md); it can go
        /// before the release, with the hashes updated.
        var runDestination: String?

        /// Which way up this note's pages are — a `PageOrientation` raw value, or
        /// `nil` for a note that has never chosen, which is portrait.
        ///
        /// Stored as a string so existing notes migrate without a mapping. A
        /// note keeps whatever it is given rather than following a default:
        /// orientation sets where lines wrap, and a default that changed would
        /// re-wrap every note that had never chosen.
        var pageOrientation: String?

        /// The folder this note is filed in, or `nil` for a note at the top of
        /// the list. A note is in one folder at most: grouping by class wants
        /// nothing more, and a note in several folders would make "move" and
        /// deleting a folder with its notes ambiguous. The other side, and the
        /// delete rule, are on `Folder.pages`.
        var folder: Folder?

        /// Whether the note is pinned to the top of the list.
        var isPinned: Bool = false

        /// Whether the note's text is locked: it can be read, selected and
        /// copied, but not typed into, and tapping it brings up no keyboard.
        /// For reading old notes without changing them by accident. Ink is
        /// left alone, so a locked note can still be drawn on.
        ///
        /// Part of the note, not the device, so it stays locked until it's
        /// unlocked. Like pinning, locking isn't an edit and keeps the date.
        var isTextLocked: Bool = false

        /// When the note was moved to Recently Deleted, or `nil` for a note
        /// that is where the reader left it. A note with a date is out of every
        /// list, search and count (`isLive`) and is purged for good 30 days
        /// after it (`Page.retention`).
        var deletedAt: Date?

        /// The body text's size in points, or `nil` for the default 17. It sets
        /// where lines break; the text options row changes it, and asks first
        /// when the note has ink.
        var textSize: Int?

        /// Unused since 31 Oct, when paper styles (dots, grid, lined) came out
        /// of the 1.0 release: every note shows plain paper. It held a
        /// `PaperSetup`'s stored string. Kept so version 1's hashes stay as
        /// they are (docs/design/the-model.md); it can go before the release,
        /// with the hashes updated.
        var paperStyle: String?

        /// The points each prose line is made taller than the font makes it,
        /// or `nil` for none (`NoteTypography.lineSpacings`). Line height only.
        /// Like the text size it moves lines under the ink, so the text row
        /// asks first when the note has ink, and it isn't an edit.
        var lineSpacing: Int?

        /// The size and spacing the note is laid out in.
        var typography: NoteTypography { NoteTypography(bodySize: textSize, lineSpacing: lineSpacing) }

        /// The fewest pages the note has, whatever it holds: what Add Page raises,
        /// and what seamless raises when ink reaches the last page, so there is
        /// always a blank page to draw on below. Only ever grows. The note has
        /// the more of this and the pages its text and ink need
        /// (`PageLayout.pageCount`). Like the text size it isn't an edit and
        /// leaves `modifiedAt` alone.
        var minimumPageCount: Int = 1

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
}
