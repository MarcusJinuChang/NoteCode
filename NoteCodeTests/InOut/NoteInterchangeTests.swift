//
//  NoteInterchangeTests.swift
//  NoteCodeTests
//
//  v3 phase 7: notes in and out as files, and one editor per note.
//

import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import NoteCode

// MARK: - File names

@Suite("Note file names")
struct NoteFileNameTests {

    @Test("Characters a file name can't hold become hyphens", arguments: [
        ("Lecture 4: Heaps/Stacks", "Lecture 4- Heaps-Stacks"),
        ("a\\b", "a-b"),
        ("Binary search", "Binary search"),
    ])
    func separators(title: String, stem: String) {
        #expect(NoteFileName.stem(for: title) == stem)
    }

    @Test("A blank title is Untitled, and a leading dot would hide the file")
    func blankAndHidden() {
        #expect(NoteFileName.stem(for: "   ") == "Untitled")
        #expect(NoteFileName.stem(for: "") == "Untitled")
        #expect(NoteFileName.stem(for: "...") == "Untitled")
        #expect(NoteFileName.stem(for: ".env notes") == "env notes")
    }

    @Test("Control characters go, and a long title is cut")
    func controlAndLength() {
        #expect(NoteFileName.stem(for: "two\nlines\t!") == "twolines!")
        let long = String(repeating: "word ", count: 60)
        let stem = NoteFileName.stem(for: long)
        #expect(stem.count <= NoteFileName.maxStemLength)
        #expect(!stem.hasSuffix(" "))
    }

    @Test("The PDF's file name still comes out the same")
    func pdfName() {
        #expect(NoteFileName.fileName(for: "Lecture 4: Heaps/Stacks", extension: "pdf") == "Lecture 4- Heaps-Stacks.pdf")
    }
}

// MARK: - Markdown out

@Suite("Markdown export")
struct NoteMarkdownTests {

    @Test("The file is the note's text, byte for byte", arguments: [
        "# Heading\n\nSome **bold** text\n",
        "```cpp\nint main() { return 0; }\n```\n",
        "no trailing newline",
        "windows\r\nline endings\r\n",
        "héllo — 日本語 🎉\n",
        "",
    ])
    func equalsContent(content: String) {
        let data = NoteMarkdown.data(for: content)
        #expect(String(decoding: data, as: UTF8.self) == content)
        #expect(data == Data(content.utf8))
    }

    @Test("It is written under the note's name, as .md")
    func written() throws {
        let url = try NoteMarkdown.write("# Hi\n", title: "Week 6: Hash tables")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent == "Week 6- Hash tables.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Hi\n")
    }
}

// MARK: - Export All's layout

@Suite("Export All layout")
struct NoteExportPlanTests {

    private typealias Item = NoteExport.Item

    @Test("A subfolder for each folder, and a note beside or inside")
    func shape() {
        let plan = NoteExport.plan(
            folderNames: ["CS133", "Algorithm practice"],
            items: [
                Item(folder: 0, title: "Week 6 · Hash tables"),
                Item(folder: 1, title: "Two pointers"),
                Item(folder: nil, title: "Big-O cheat sheet"),
            ]
        )
        #expect(plan.directories == ["CS133", "Algorithm practice"])
        #expect(plan.entries.map(\.directory) == ["CS133", "Algorithm practice", nil])
        #expect(plan.entries.map(\.markdownName) == ["Week 6 · Hash tables.md", "Two pointers.md", "Big-O cheat sheet.md"])
    }

    @Test("A note's PDF sits beside its Markdown under the same stem")
    func pdfBesideMarkdown() {
        let plan = NoteExport.plan(folderNames: [], items: [Item(folder: nil, title: "Heaps")])
        #expect(plan.entries[0].markdownName == "Heaps.md")
        #expect(plan.entries[0].pdfName == "Heaps.pdf")
    }

    @Test("Two notes of one title don't overwrite each other, ignoring case")
    func duplicateTitles() {
        let plan = NoteExport.plan(
            folderNames: [],
            items: [
                Item(folder: nil, title: "Untitled"),
                Item(folder: nil, title: "untitled"),
                Item(folder: nil, title: "Untitled"),
            ]
        )
        #expect(plan.entries.map(\.stem) == ["Untitled", "untitled 2", "Untitled 3"])
    }

    @Test("The same title in two folders is not a collision")
    func sameTitleInTwoFolders() {
        let plan = NoteExport.plan(
            folderNames: ["A", "B"],
            items: [Item(folder: 0, title: "Notes"), Item(folder: 1, title: "Notes")]
        )
        #expect(plan.entries.map(\.stem) == ["Notes", "Notes"])
    }

    @Test("Two folders of one name get separate directories")
    func duplicateFolders() {
        let plan = NoteExport.plan(
            folderNames: ["CS133", "cs133"],
            items: [Item(folder: 0, title: "a"), Item(folder: 1, title: "b")]
        )
        #expect(plan.directories == ["CS133", "cs133 2"])
        #expect(plan.entries.map(\.directory) == ["CS133", "cs133 2"])
    }

    @Test("A folder with no notes is still a directory")
    func emptyFolder() {
        let plan = NoteExport.plan(folderNames: ["Empty"], items: [])
        #expect(plan.directories == ["Empty"])
        #expect(plan.entries.isEmpty)
    }

    @Test("A folder name is made safe like a note's")
    func folderNameIsSanitised() {
        let plan = NoteExport.plan(folderNames: ["CS133/Week 1"], items: [Item(folder: 0, title: "x")])
        #expect(plan.directories == ["CS133-Week 1"])
    }

    @Test("A note pointing at a folder that isn't there goes to the top")
    func strayFolderIndex() {
        let plan = NoteExport.plan(folderNames: ["A"], items: [Item(folder: 5, title: "x")])
        #expect(plan.entries[0].directory == nil)
    }

    @Test("The root is the day's date")
    func rootName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        #expect(NoteExport.rootName(on: date, calendar: calendar) == "NoteCode 2026-10-14")
    }

    @Test("The preview lists folders first, then loose notes, each indented")
    func tree() {
        let plan = NoteExport.plan(
            folderNames: ["CS133", "Algorithm practice"],
            items: [
                Item(folder: 0, title: "Week 6"),
                Item(folder: 1, title: "Two pointers"),
                Item(folder: nil, title: "Big-O cheat sheet"),
            ]
        )
        #expect(NoteExport.tree(of: plan, root: "NoteCode 2026-10-14") == """
        NoteCode 2026-10-14/
          Algorithm practice/
            Two pointers.md
          CS133/
            Week 6.md
          Big-O cheat sheet.md
        """)
    }

    @Test("A long preview stops, and says how much more there is")
    func longTree() {
        let items = (1...40).map { Item(folder: nil, title: "Note \($0)") }
        let tree = NoteExport.tree(of: NoteExport.plan(folderNames: [], items: items), root: "Root", limit: 6)
        let lines = tree.split(separator: "\n")
        #expect(lines.count == 6)
        #expect(lines.last == "  … and 36 more")
    }
}

// MARK: - Import's tagging and titles

@Suite("Import")
struct NoteImportTests {

    @Test("A source file is one block tagged from its extension", arguments: [
        ("lab3.cpp", CodeLanguage.cpp),
        ("lab3.cc", .cpp),
        ("shapes.h", .cpp),
        ("shapes.hpp", .cpp),
        ("util.c", .c),
        ("Main.java", .java),
        ("two_sum.py", .python),
        ("app.js", .javascript),
        ("main.rs", .rust),
        ("main.go", .go),
        ("query.sql", .sql),
        ("SHOUT.PY", .python),
    ])
    func tagged(fileName: String, language: CodeLanguage) throws {
        let note = try #require(NoteImport.note(fileName: fileName, text: "body\n"))
        #expect(note.content == "```\(language.rawValue)\nbody\n```\n")

        // And the app reads it back as exactly that: one closed block in that
        // language, which is what gives it highlighting and Run.
        let blocks = DocumentParser.parse(note.content).compactMap(\.codeBlock)
        #expect(blocks.count == 1)
        #expect(blocks.first?.language == language)
    }

    @Test("The title is the file's name without its extension", arguments: [
        ("two_sum.py", "two_sum"),
        ("lab3.cpp", "lab3"),
        ("exam-notes.md", "exam-notes"),
        ("v1.2 notes.txt", "v1.2 notes"),
    ])
    func titled(fileName: String, title: String) throws {
        #expect(try #require(NoteImport.note(fileName: fileName, text: "x")).title == title)
    }

    @Test("Markdown and text come in as written", arguments: ["a.md", "a.markdown", "a.txt"])
    func asWritten(fileName: String) throws {
        let text = "# Heading\n\n- one\n- two\n\n```python\nprint(1)\n```\n"
        #expect(try #require(NoteImport.note(fileName: fileName, text: text)).content == text)
    }

    @Test("Windows line endings and a byte order mark are taken out")
    func normalised() throws {
        let note = try #require(NoteImport.note(fileName: "a.md", text: "\u{FEFF}one\r\ntwo\rthree"))
        #expect(note.content == "one\ntwo\nthree")
        let code = try #require(NoteImport.note(fileName: "a.py", text: "x = 1\r\ny = 2"))
        #expect(code.content == "```python\nx = 1\ny = 2\n```\n")
    }

    @Test("Code that mentions a fence gets a wider one, so it stays one block")
    func fenceInsideCode() throws {
        let source = "print('''\n```\nnot the end\n```\n''')\n"
        let note = try #require(NoteImport.note(fileName: "doc.py", text: source))
        #expect(note.content.hasPrefix("````python\n"))
        let blocks = DocumentParser.parse(note.content).compactMap(\.codeBlock)
        #expect(blocks.count == 1)
        #expect(blocks.first?.language == .python)
    }

    @Test("An empty source file is an empty block, not a broken one")
    func emptySource() throws {
        let note = try #require(NoteImport.note(fileName: "empty.c", text: ""))
        #expect(note.content == "```c\n```\n")
        #expect(DocumentParser.parse(note.content).compactMap(\.codeBlock).count == 1)
    }

    @Test("Other kinds of file aren't taken", arguments: ["photo.png", "notes.docx", "Makefile", "script.swift", "a.pdf"])
    func unsupported(fileName: String) {
        #expect(NoteImport.note(fileName: fileName, text: "x") == nil)
        #expect(!NoteImport.isSupported(fileName: fileName))
    }

    @Test("The brief's extensions are all supported")
    func theBriefsList() {
        for ext in ["md", "txt", "cpp", "cc", "h", "hpp", "c", "java", "py", "js", "rs", "go", "sql"] {
            #expect(NoteImport.isSupported(fileName: "f.\(ext)"), "\(ext)")
        }
        #expect(NoteImport.contentTypes.count >= 10)
    }

    @Test("Bytes are read as UTF-8 or marked UTF-16, and a binary file is refused")
    func decoding() {
        #expect(NoteImport.text(from: Data("héllo".utf8)) == "héllo")
        #expect(NoteImport.text(from: "héllo".data(using: .utf16)!) == "héllo")
        #expect(NoteImport.text(from: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01])) == nil)
        #expect(NoteImport.text(from: Data(repeating: 0x61, count: NoteImport.maxBytes + 1)) == nil)
    }
}

// MARK: - Import into the store

@Suite("Import into notes")
@MainActor
struct ImportFilesTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let directory: URL

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        directory = FileManager.default.temporaryDirectory
            .appending(path: "ImportTests \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(_ name: String, _ contents: some DataProtocol) throws -> URL {
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        try Data(contents).write(to: url)
        return url
    }

    @Test("Each file becomes a note in the folder, like a new note")
    func notesInTheFolder() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = Folder(name: "CS133")
        context.insert(folder)
        let urls = [
            try file("two_sum.py", Data("def f(): pass\n".utf8)),
            try file("exam-notes.md", Data("# Exam\n".utf8)),
        ]

        let result = Page.importFiles(urls, orientation: .landscape, into: folder, context: context)

        #expect(result.pages.map(\.title) == ["two_sum", "exam-notes"])
        #expect(result.pages.map(\.content) == ["```python\ndef f(): pass\n```\n", "# Exam\n"])
        #expect(result.pages.allSatisfy { $0.folder === folder })
        #expect(result.pages.allSatisfy { $0.orientation == .landscape })
        #expect(result.skipped.isEmpty)
        #expect(result.summary(into: folder) == "Imported 2 notes into CS133")
        #expect(folder.livePages.count == 2)
    }

    @Test("A note at the top of the list says so without a folder")
    func summaryWithoutFolder() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = Page.importFiles([try file("a.txt", Data("x".utf8))], orientation: .portrait, into: nil, context: context)
        #expect(result.summary(into: nil) == "Imported 1 note")
        #expect(result.pages[0].folder == nil)
    }

    @Test("A file that can't come in is skipped with a reason and the rest come in")
    func skips() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [
            try file("good.md", Data("ok".utf8)),
            try file("picture.png", Data([0x89, 0x50])),
            try file("binary.txt", Data([0x00, 0x01, 0x02])),
            directory.appending(path: "missing.md", directoryHint: .notDirectory),
        ]

        let result = Page.importFiles(urls, orientation: .portrait, into: nil, context: context)

        #expect(result.pages.map(\.title) == ["good"])
        #expect(result.skipped.map(\.name) == ["picture.png", "binary.txt", "missing.md"])
        let message = try #require(result.skippedMessage)
        #expect(message.contains("picture.png"))
        #expect(message.contains("missing.md"))
        #expect(result.summary(into: nil) == "Imported 1 note")
    }

    @Test("Nothing imported has no summary")
    func nothing() {
        #expect(NoteImportResult().summary(into: nil) == nil)
        #expect(NoteImportResult().skippedMessage == nil)
    }

    @Test("Importing doesn't touch the notes already there")
    func otherNotesKeepTheirDates() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = Page(title: "Old", content: "old", createdAt: before)
        context.insert(existing)

        Page.importFiles([try file("a.md", Data("x".utf8))], orientation: .portrait, into: nil, context: context)

        #expect(existing.modifiedAt == before)
        #expect(existing.content == "old")
    }
}

// MARK: - Export All's files

@Suite("Export All folder")
@MainActor
struct NoteExportJobTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    @discardableResult
    private func note(_ title: String, _ content: String, in folder: Folder? = nil, age: Double = 0) -> Page {
        let page = Page(title: title, content: content, createdAt: Date(timeIntervalSince1970: 1_700_000_000 + age))
        context.insert(page)
        page.folder = folder
        return page
    }

    /// Runs a job to the end and answers where its folder is.
    private func run(_ job: NoteExportJob, pages: [Page], folders: [Folder], pdfs: Bool = false) async throws -> URL {
        job.start(pages: pages, folders: folders, includePDFs: pdfs)
        for _ in 0..<2000 {
            if case .ready = job.state { break }
            if case .failed(let message) = job.state { Issue.record("failed: \(message)"); break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .ready = job.state else { throw CocoaError(.fileNoSuchFile) }
        return try #require(await Self.root(of: job))
    }

    /// The folder the document points at, found through its snapshot.
    private static func root(of job: NoteExportJob) async -> URL? {
        // A wrapper made from a URL keeps no path, so the job's folder is read
        // by writing the snapshot out, as the exporter does.
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ExportRead \(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            let snapshot = try await job.document.snapshot(contentType: .folder)
            try snapshot.write(to: destination, options: .atomic, originalContentsURL: nil)
            return destination
        } catch {
            return nil
        }
    }

    private func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    @Test("A subfolder per folder, a Markdown file per note, equal to its text")
    func folderLayout() async throws {
        let cs = Folder(name: "CS133")
        context.insert(cs)
        let empty = Folder(name: "Empty")
        context.insert(empty)
        let pages = [
            note("Week 6", "# Hash tables\n\n```cpp\nint x;\n```\n", in: cs, age: 1),
            note("Big-O", "O(n log n)", age: 2),
            note("Big-O", "second of the name", age: 3),
        ]

        let job = NoteExportJob()
        let root = try await run(job, pages: pages, folders: [cs, empty])
        defer { try? FileManager.default.removeItem(at: root); job.cleanUp() }

        #expect(try names(in: root) == ["Big-O 2.md", "Big-O.md", "CS133", "Empty"])
        #expect(try names(in: root.appending(path: "CS133")) == ["Week 6.md"])
        #expect(try names(in: root.appending(path: "Empty")).isEmpty)
        #expect(try String(contentsOf: root.appending(path: "CS133/Week 6.md"), encoding: .utf8) == pages[0].content)
        #expect(try String(contentsOf: root.appending(path: "Big-O.md"), encoding: .utf8) == "O(n log n)")
        #expect(try String(contentsOf: root.appending(path: "Big-O 2.md"), encoding: .utf8) == "second of the name")
    }

    @Test("Notes in Recently Deleted are left out when the caller passes the live ones")
    func deletedLeftOut() async throws {
        let kept = note("Kept", "k", age: 1)
        let gone = note("Gone", "g", age: 2)
        try Page.moveToRecentlyDeleted([gone], from: context)

        let job = NoteExportJob()
        let root = try await run(job, pages: [kept, gone].live, folders: [])
        defer { try? FileManager.default.removeItem(at: root); job.cleanUp() }

        #expect(try names(in: root) == ["Kept.md"])
    }

    @Test("The exported folder is a WritableDocument whose snapshot is a directory")
    func documentSnapshot() async throws {
        #expect(ExportFolderDocument.writableContentTypes == [.folder])
        let empty = try await ExportFolderDocument().snapshot(contentType: .folder)
        #expect(empty.isDirectory)
        #expect(empty.fileWrappers?.isEmpty == true)

        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Snapshot \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("hello".utf8).write(to: folder.appending(path: "a.md"))
        let wrapper = try await ExportFolderDocument(folder: folder).snapshot(contentType: .folder)
        #expect(wrapper.isDirectory)
        #expect(wrapper.fileWrappers?["a.md"]?.regularFileContents == Data("hello".utf8))
    }

    @Test("Cancelling removes what was written and leaves the job idle")
    func cancelling() async throws {
        let pages = (0..<30).map { note("Note \($0)", String(repeating: "line\n", count: 50), age: Double($0)) }

        let job = NoteExportJob()
        job.start(pages: pages, folders: [], includePDFs: false)
        #expect(job.isWorking)
        job.cancel()
        #expect(job.state == .idle)

        // Give the unwound run time to finish; it must not report anything.
        try await Task.sleep(for: .milliseconds(300))
        #expect(job.state == .idle)
    }

    /// A behaviour check, not proof of `NoteExportJob`'s `generation` guard:
    /// with the guard taken out this still passes (tried 14 Oct), because the
    /// cancelled run and the new one never interleave visibly at this size.
    @Test("An export started right after a cancel still completes")
    func restartAfterCancel() async throws {
        let pages = (0..<10).map { note("Note \($0)", "text", age: Double($0)) }
        let job = NoteExportJob()
        job.start(pages: pages, folders: [], includePDFs: false)
        // Let the first run get into its loop, so it is suspended between
        // notes when it is cancelled and finds out only when it wakes.
        for _ in 0..<500 {
            if case .working(let done, _) = job.state, done >= 1 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        job.cancel()

        let root = try await run(job, pages: pages, folders: [])
        defer { try? FileManager.default.removeItem(at: root); job.cleanUp() }
        #expect(try names(in: root).count == 10)
    }

    #if canImport(UIKit)
    @Test("A PDF is added beside a note that has ink, and only that note")
    func pdfForInk() async throws {
        let inked = note("Sketch", "# Sketch\n", age: 1)
        inked.drawingData = try await DrawingCodec.encode(TestInk.markup(strokesAt: [300]))
        let plain = note("Plain", "just text", age: 2)

        let job = NoteExportJob()
        let root = try await run(job, pages: [inked, plain], folders: [], pdfs: true)
        defer { try? FileManager.default.removeItem(at: root); job.cleanUp() }

        #expect(try names(in: root) == ["Plain.md", "Sketch.md", "Sketch.pdf"])
        let pdf = try Data(contentsOf: root.appending(path: "Sketch.pdf"))
        #expect(pdf.starts(with: Array("%PDF".utf8)))
    }

    @Test("With PDFs off, a note with ink gets only its Markdown")
    func noPDFsWhenOff() async throws {
        let inked = note("Sketch", "# Sketch\n")
        inked.drawingData = try await DrawingCodec.encode(TestInk.markup(strokesAt: [300]))

        let job = NoteExportJob()
        let root = try await run(job, pages: [inked], folders: [], pdfs: false)
        defer { try? FileManager.default.removeItem(at: root); job.cleanUp() }

        #expect(try names(in: root) == ["Sketch.md"])
    }
    #endif
}

// MARK: - One editor per note

@Suite("One editor per note")
@MainActor
struct OpenNoteRegistryTests {

    @Test("The first window to open a note has it, and a second can't")
    func firstWins() {
        let registry = OpenNoteRegistry()
        let a = WindowToken(), b = WindowToken()

        #expect(registry.claim("note", for: a))
        #expect(!registry.claim("note", for: b))
        #expect(registry.holder(of: "note") === a)
        #expect(registry.isOpenElsewhere("note", for: b))
        #expect(!registry.isOpenElsewhere("note", for: a))
    }

    @Test("Claiming again from the same window is fine")
    func idempotent() {
        let registry = OpenNoteRegistry()
        let a = WindowToken()
        #expect(registry.claim("note", for: a))
        #expect(registry.claim("note", for: a))
    }

    @Test("Different notes don't interfere")
    func differentNotes() {
        let registry = OpenNoteRegistry()
        let a = WindowToken(), b = WindowToken()
        #expect(registry.claim("one", for: a))
        #expect(registry.claim("two", for: b))
        #expect(!registry.isOpenElsewhere("two", for: b))
    }

    @Test("Letting a note go frees it for the other window")
    func release() {
        let registry = OpenNoteRegistry()
        let a = WindowToken(), b = WindowToken()
        registry.claim("note", for: a)

        registry.release("note", by: b)
        #expect(registry.holder(of: "note") === a, "a window can't release another's note")

        registry.release("note", by: a)
        #expect(registry.holder(of: "note") == nil)
        #expect(registry.claim("note", for: b))
    }

    @Test("A window that is gone no longer holds anything")
    func windowGone() async {
        let registry = OpenNoteRegistry()
        let b = WindowToken()
        var a: WindowToken? = WindowToken()
        registry.claim("note", for: a!)
        #expect(registry.isOpenElsewhere("note", for: b))

        a = nil
        #expect(registry.holder(of: "note") == nil)
        #expect(!registry.isOpenElsewhere("note", for: b))
        #expect(registry.claim("note", for: b))
    }

    @Test("Sweeping drops the dead claims")
    func sweep() {
        let registry = OpenNoteRegistry()
        var a: WindowToken? = WindowToken()
        registry.claim("note", for: a!)
        a = nil
        registry.sweep()
        #expect(registry.holder(of: "note") == nil)
    }

    @Test("A note's key is the same from two contexts, which is what the guard compares")
    func keysAreSharedAcrossContexts() throws {
        let schema = NoteSchema.current
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let page = Page(title: "x")
        container.mainContext.insert(page)
        try container.mainContext.save()

        let other = ModelContext(container)
        let sameNote = try #require(other.model(for: page.persistentModelID) as? Page)

        #expect(sameNote !== page)
        let key = try #require(NoteMemory.key(for: page.persistentModelID))
        #expect(key == NoteMemory.key(for: sameNote.persistentModelID))
    }
}
