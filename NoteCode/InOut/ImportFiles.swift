//
//  ImportFiles.swift
//  NoteCode
//
//  Import: files from the Files app become notes.
//

import Foundation
import SwiftData

/// What an import made, and what it couldn't.
struct NoteImportResult {
    var pages: [Page] = []
    /// A file that wasn't imported, and why, in words for the reader.
    var skipped: [(name: String, reason: String)] = []

    /// "Imported 3 notes into CS133": the toast. `nil` when nothing came in.
    func summary(into folder: Folder?) -> String? {
        guard !pages.isEmpty else { return nil }
        let count = pages.count == 1 ? "1 note" : "\(pages.count) notes"
        return folder.map { "Imported \(count) into \($0.name)" } ?? "Imported \(count)"
    }

    /// The skipped files for an alert, one to a line.
    var skippedMessage: String? {
        guard !skipped.isEmpty else { return nil }
        return skipped.map { "\($0.name): \($0.reason)" }.joined(separator: "\n")
    }
}

extension Page {

    /// Makes a note of each file, filed in `folder`, through `Page.create` so
    /// each is a note like any other (the same orientation and Markdown layout).
    ///
    /// The URLs come from the file importer, which hands over access to them
    /// only for as long as it is asked to (security-scoped), so each is opened
    /// and closed here. A file that can't be read, isn't text, is too big or
    /// isn't a kind Import takes is skipped with its reason and the rest come
    /// in.
    @MainActor
    @discardableResult
    static func importFiles(
        _ urls: [URL],
        orientation: PageOrientation,
        into folder: Folder?,
        context: ModelContext
    ) -> NoteImportResult {
        var result = NoteImportResult()
        for url in urls {
            let name = url.lastPathComponent
            guard NoteImport.isSupported(fileName: name) else {
                result.skipped.append((name, "NoteCode doesn't import this kind of file."))
                continue
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                result.skipped.append((name, "It couldn't be read."))
                continue
            }
            guard data.count <= NoteImport.maxBytes else {
                result.skipped.append((name, "It's too big to be a note."))
                continue
            }
            guard let text = NoteImport.text(from: data),
                  let imported = NoteImport.note(fileName: name, text: text)
            else {
                result.skipped.append((name, "It isn't text NoteCode can read."))
                continue
            }

            let page = create(orientation: orientation, in: folder, context: context)
            page.title = imported.title
            page.content = imported.content
            result.pages.append(page)
        }
        return result
    }
}
