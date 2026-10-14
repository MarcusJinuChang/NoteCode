//
//  NoteInterchange.swift
//  NoteCode
//
//  Getting notes in and out as files (v3 phase 7). Pure: strings and lists in,
//  strings and lists out, so the folder layout, the file names and the import's
//  tagging are tested with no view, store or file system around them.
//

import Foundation
import UniformTypeIdentifiers

/// File names for notes that leave the app.
nonisolated enum NoteFileName {

    /// The longest a name's stem may be, in characters. File systems allow 255
    /// bytes for the whole name; leaving room for " 12.markdown" and for a
    /// title of wide characters.
    static let maxStemLength = 80

    /// A note's title as a file name, without its extension.
    ///
    /// `/`, `\` and `:` become `-` (the first two split a path, the third is
    /// a folder separator in Files on the Mac). A leading `.` is dropped, or
    /// the file would be hidden, and so is anything that isn't printable.
    /// Never blank: a title of spaces is "Untitled".
    static func stem(for title: String) -> String {
        let separated = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
        var cleaned = String(String.UnicodeScalarView(
            separated.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        )).trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > maxStemLength {
            cleaned = String(cleaned.prefix(maxStemLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    static func fileName(for title: String, extension ext: String) -> String {
        stem(for: title) + "." + ext
    }
}

/// A note's text as a Markdown file.
nonisolated enum NoteMarkdown {

    /// The file's bytes: the note's text and nothing else. "Markdown export
    /// equals content" (the brief), so a title isn't added as a heading and
    /// line endings aren't touched.
    static func data(for content: String) -> Data {
        Data(content.utf8)
    }

    /// Writes the `.md` where the share sheet can hand it on, named for the
    /// note. Replaces an earlier share of the same title.
    static func write(_ content: String, title: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Shared Markdown", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: NoteFileName.fileName(for: title, extension: "md"), directoryHint: .notDirectory)
        try data(for: content).write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Export

/// What Export All writes, decided before anything is written.
nonisolated enum NoteExport {

    /// One note, as the plan needs to know it.
    struct Item: Equatable, Sendable {
        /// The index in `folderNames` of the note's folder, or `nil` for a
        /// note at the top of the list.
        var folder: Int?
        var title: String
    }

    /// Where one note goes: a directory (`nil` for the top level) and the
    /// name, without extension, its `.md` and `.pdf` share.
    struct Entry: Equatable, Sendable {
        /// The index of the note in the plan's input.
        var item: Int
        var directory: String?
        var stem: String

        var markdownName: String { stem + ".md" }
        var pdfName: String { stem + ".pdf" }
    }

    struct Plan: Equatable, Sendable {
        /// A subfolder for every folder, including one with no notes, so the
        /// export has the shape of the list. Unique, in the order given.
        var directories: [String]
        var entries: [Entry]
    }

    /// The layout of an export: a subfolder for each folder and a Markdown
    /// file for each note.
    ///
    /// Names are made unique where they would collide, within one directory
    /// and ignoring case, since Files on the Mac and the iPad's volumes are
    /// case-insensitive: the second "Two pointers" is "Two pointers 2". The
    /// `.md` and the `.pdf` of a note share its stem, so they sit together.
    /// Which of two notes of one title gets the bare name is the order they
    /// are given in; the caller passes them oldest first, so a re-export
    /// names them the same.
    static func plan(folderNames: [String], items: [Item]) -> Plan {
        var directories: [String] = []
        var directoryNames = UniqueNames()
        for name in folderNames {
            directories.append(directoryNames.claim(NoteFileName.stem(for: name)))
        }

        var stems: [String?: UniqueNames] = [:]
        var entries: [Entry] = []
        for (index, item) in items.enumerated() {
            let directory = item.folder.flatMap { directories.indices.contains($0) ? directories[$0] : nil }
            var names = stems[directory] ?? UniqueNames()
            let stem = names.claim(NoteFileName.stem(for: item.title))
            stems[directory] = names
            entries.append(Entry(item: index, directory: directory, stem: stem))
        }
        return Plan(directories: directories, entries: entries)
    }

    /// The export's top folder: "NoteCode 2026-10-14".
    static func rootName(on date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "NoteCode %04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The plan as the sheet shows it, one line per file and folder: folders
    /// first in name order, then the notes at the top, each folder's notes
    /// indented under it.
    ///
    /// Stops after `limit` lines with a count of the rest, since a semester of
    /// notes is hundreds of lines in a sheet.
    static func tree(of plan: Plan, root: String, limit: Int = 12) -> String {
        var lines = ["\(root)/"]
        let byDirectory = Dictionary(grouping: plan.entries, by: \.directory)
        func notes(in directory: String?) -> [String] {
            (byDirectory[directory] ?? []).map(\.markdownName).sorted(by: compare)
        }
        for directory in plan.directories.sorted(by: compare) {
            lines.append("  \(directory)/")
            lines += notes(in: directory).map { "    \($0)" }
        }
        lines += notes(in: nil).map { "  \($0)" }

        guard lines.count > limit else { return lines.joined(separator: "\n") }
        let more = lines.count - (limit - 1)
        return (lines.prefix(limit - 1) + ["  … and \(more) more"]).joined(separator: "\n")
    }

    private static func compare(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    /// Hands out names, adding " 2", " 3" to one already taken.
    private struct UniqueNames {
        private var taken: Set<String> = []

        mutating func claim(_ name: String) -> String {
            var candidate = name
            var number = 2
            while taken.contains(candidate.lowercased()) {
                candidate = "\(name) \(number)"
                number += 1
            }
            taken.insert(candidate.lowercased())
            return candidate
        }
    }
}

// MARK: - Import

/// What a file becomes when it is imported.
nonisolated enum NoteImport {

    struct Imported: Equatable, Sendable {
        var title: String
        var content: String
    }

    /// Extensions that come in as written: Markdown and plain text.
    static let textExtensions: Set<String> = ["md", "markdown", "txt"]

    /// Source files, and the language each is tagged as. `.h` is C++: the
    /// course is C++, and a C header is rarely a note.
    static let sourceLanguages: [String: CodeLanguage] = [
        "cpp": .cpp, "cc": .cpp, "h": .cpp, "hpp": .cpp,
        "c": .c,
        "java": .java,
        "py": .python,
        "js": .javascript,
        "rs": .rust,
        "go": .go,
        "sql": .sql,
    ]

    /// Every extension Import accepts.
    static var supportedExtensions: [String] {
        (textExtensions.sorted() + sourceLanguages.keys.sorted())
    }

    /// The largest file Import reads. A text file this big is a mistake (a log,
    /// a dump), and the note it made would lay out for minutes.
    static let maxBytes = 2_000_000

    /// What the file picker lets the reader choose: each supported extension's
    /// type, which also covers a type the system doesn't know by name.
    static var contentTypes: [UTType] {
        supportedExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func isSupported(fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return textExtensions.contains(ext) || sourceLanguages[ext] != nil
    }

    /// The note a file becomes, or `nil` for a name Import doesn't take.
    ///
    /// The title is the file's name without its extension. Markdown and text
    /// are the note as written; a source file is one fenced block tagged with
    /// its language, so it opens highlighted and with Run.
    static func note(fileName: String, text: String) -> Imported? {
        let name = fileName as NSString
        let ext = name.pathExtension.lowercased()
        let title = Page.title(fromTyped: name.deletingPathExtension)
        let body = normalised(text)

        if textExtensions.contains(ext) {
            return Imported(title: title, content: body)
        }
        guard let language = sourceLanguages[ext] else { return nil }

        // The fence is one backtick longer than any run of them that starts a
        // line in the code, or that line would close the block early (the
        // parser closes on a bare fence at least as wide as the opening one).
        let width = max(3, longestFenceRun(in: body) + 1)
        let fence = String(repeating: "`", count: width)
        let code = body.isEmpty || body.hasSuffix("\n") ? body : body + "\n"
        return Imported(title: title, content: "\(fence)\(language.rawValue)\n\(code)\(fence)\n")
    }

    /// A file's bytes as text: UTF-8, or UTF-16 with a byte order mark, which
    /// Notepad and some exports write. `nil` for anything else, or for bytes
    /// with a NUL in them, which is a binary file.
    static func text(from data: Data) -> String? {
        guard data.count <= maxBytes, !data.contains(0) || hasUTF16Mark(data) else { return nil }
        if hasUTF16Mark(data) {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8)
    }

    private static func hasUTF16Mark(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
    }

    /// Line endings as the editor writes them, and no byte order mark.
    private static func normalised(_ text: String) -> String {
        var result = text
        if result.hasPrefix("\u{FEFF}") { result.removeFirst() }
        return result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func longestFenceRun(in text: String) -> Int {
        var longest = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.drop { $0 == " " }
            longest = max(longest, trimmed.prefix { $0 == "`" }.count)
        }
        return longest
    }
}

// MARK: - One editor per note

/// Which window has which note open, so two windows never edit one note.
///
/// A scene is a window; `NavigationSplitView` in each one keeps its own
/// selection, and nothing stopped two windows selecting the same note. Both
/// would then write its text and ink, and the later save would win, silently.
/// Instead the first window to open a note claims it, and a second window that
/// selects it shows "Open in another window" in place of the editor.
///
/// **Keys, not notes.** A claim is kept by `NoteMemory.key(for:)`, a string
/// that two contexts' copies of one note share, where the objects don't compare.
///
/// **A window is a token, held weakly.** A window the system discards never
/// tells anyone, so a claim names a `WindowToken` the window holds in its
/// state; when the scene goes, the token does, and its claims stop counting
/// (`holder(of:)` skips a dead one) without anything having to run.
@MainActor
@Observable
final class OpenNoteRegistry {
    static let shared = OpenNoteRegistry()

    private struct Claim {
        weak var window: WindowToken?
    }

    private var claims: [String: Claim] = [:]

    /// The window that has the note open, if any is still there.
    func holder(of key: String) -> WindowToken? {
        claims[key]?.window
    }

    /// Whether another window has the note open, so this one mustn't.
    func isOpenElsewhere(_ key: String, for window: WindowToken) -> Bool {
        guard let holder = holder(of: key) else { return false }
        return holder !== window
    }

    /// Takes the note for `window` if no other window has it.
    ///
    /// - Returns: whether `window` has it now.
    @discardableResult
    func claim(_ key: String, for window: WindowToken) -> Bool {
        if let holder = holder(of: key), holder !== window { return false }
        claims[key] = Claim(window: window)
        return true
    }

    /// Gives the note up, if `window` is the one holding it.
    func release(_ key: String, by window: WindowToken) {
        guard claims[key]?.window === window else { return }
        claims[key] = nil
    }

    /// Forgets claims whose window is gone, so the table doesn't grow and
    /// anything watching `holder(of:)` sees the note come free.
    func sweep() {
        for (key, claim) in claims where claim.window == nil {
            claims[key] = nil
        }
    }
}

/// One window's identity in the registry: a class, so it can be held weakly
/// and compared by identity.
@MainActor
final class WindowToken {
    init() {}

    nonisolated deinit {
        // The window is gone: let the registry drop its claims, and anyone
        // showing "Open in another window" notice that the note is free.
        Task { @MainActor in OpenNoteRegistry.shared.sweep() }
    }
}
