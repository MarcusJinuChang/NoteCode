//
//  NoteTemplatesTests.swift
//  NoteCodeTests
//
//  Phase 5 of v3: Lecture, Problem and Lab.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Note templates")
@MainActor
struct NoteTemplatesTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private static let british = Locale(identifier: "en_GB")

    /// Noon on 13 October 2026 where the test runs, so the date reads the
    /// same in any time zone.
    private static let now: Date = {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 13
        parts.hour = 12
        return Calendar.current.date(from: parts)!
    }()

    private static func headings(of content: String) -> [String] {
        DocumentParser.parse(content).compactMap { block in
            if case .heading(let level, _) = block.kind {
                // A block's range is line-aligned, newline included.
                return "\(level):\(content[block.contentRange].trimmingCharacters(in: .newlines))"
            }
            return nil
        }
    }

    private static func content(_ template: NoteTemplate, _ language: CodeLanguage = .cpp) -> String {
        template.content(language: language, now: now, locale: british)
    }

    // MARK: The text

    @Test("Each template has the headings on the board, in order")
    func headings() {
        #expect(Self.headings(of: Self.content(.lecture)) == [
            "1:Lecture [N] · [Topic]", "2:Key ideas", "2:Code", "2:Questions",
        ])
        #expect(Self.headings(of: Self.content(.problem)) == [
            "1:[Problem]", "2:Approach", "2:Complexity", "2:Mistakes",
        ])
        #expect(Self.headings(of: Self.content(.lab)) == [
            "1:Lab [N] · [Topic]", "2:Goal", "2:Steps", "2:Code", "2:Results",
        ])
    }

    @Test("Each has one closed, empty code block in the language it's given", arguments: NoteTemplate.allCases, CodeLanguage.allCases)
    func codeBlock(template: NoteTemplate, language: CodeLanguage) throws {
        let content = Self.content(template, language)
        let blocks = DocumentParser.parse(content).compactMap(\.codeBlock)

        let block = try #require(blocks.first)
        #expect(blocks.count == 1)
        #expect(block.language == language)
        #expect(block.isClosed)
        #expect(content[block.contentRange].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("A Lecture is dated, and the brackets are placeholders, not links")
    func lecture() {
        let content = Self.content(.lecture)
        #expect(content.contains("[Course] · 13 Oct"))

        func links(in content: String) -> Int {
            DocumentParser.parse(content).reduce(0) { total, block in
                total + block.inlines.filter { $0.kind == .link }.count
            }
        }
        #expect(links(in: content) == 0)
        #expect(links(in: Self.content(.lab)) == 0)
        // Problem has one real link to type over.
        #expect(links(in: Self.content(.problem)) == 1)
    }

    @Test("A Lab's steps are an unchecked list")
    func labSteps() {
        let boxes = DocumentParser.parse(Self.content(.lab)).compactMap { block -> Bool? in
            if case .listItem(_, .checkbox(let checked), _) = block.kind { return checked }
            return nil
        }
        #expect(boxes == [false, false])
    }

    @Test("Bullets are empty and ready to type in")
    func bullets() {
        let items = DocumentParser.parse(Self.content(.lecture)).filter {
            if case .listItem = $0.kind { return true }
            return false
        }
        #expect(items.count == 3)
    }

    // MARK: The language

    @Test("The code block is in the language most of a folder's blocks are, else C++")
    func commonLanguage() {
        func notes(_ tags: String...) -> [String] {
            tags.map { "```\($0)\ncode\n```" }
        }
        #expect(NoteTemplates.commonLanguage(in: [String]()) == .cpp)
        #expect(NoteTemplates.commonLanguage(in: ["Just prose"]) == .cpp)
        #expect(NoteTemplates.commonLanguage(in: notes("python", "python", "cpp")) == .python)
        #expect(NoteTemplates.commonLanguage(in: notes("java", "py", "python3", "c++")) == .python)
        // Several blocks in one note count each.
        #expect(NoteTemplates.commonLanguage(in: ["```go\n```\n```go\n```\n```rust\n```"]) == .go)
        // A tie goes to the language earlier in the menus.
        #expect(NoteTemplates.commonLanguage(in: notes("python", "java")) == .java)
        // Blocks in a language the app doesn't know, and bare ones, aren't counted.
        #expect(NoteTemplates.commonLanguage(in: notes("ruby", "ruby", "")) == .cpp)
        #expect(NoteTemplates.commonLanguage(in: notes("ruby", "ruby", "rust")) == .rust)
    }

    // MARK: Making one

    private func note(_ code: String, in folder: Folder) -> Page {
        let page = Page.create(orientation: .portrait, in: folder, context: context)
        page.content = "```\(code)\nx\n```"
        return page
    }

    @Test("A template made in a folder takes the folder's usual language")
    func fromFolder() throws {
        let folder = Folder(name: "Algorithms")
        context.insert(folder)
        _ = note("python", in: folder)
        _ = note("python", in: folder)
        _ = note("java", in: folder)

        let page = Page.create(from: .problem, orientation: .landscape, in: folder, now: Self.now, context: context)

        let block = try #require(DocumentParser.parse(page.content).compactMap(\.codeBlock).first)
        #expect(block.language == .python)
        #expect(page.title == "Problem")
        #expect(page.folder === folder)
        #expect(page.orientation == .landscape)
        #expect(page.markdownLayout == Page.renderedMarkdown)
    }

    @Test("Notes in Recently Deleted don't vote")
    func deletedNotesDontCount() throws {
        let folder = Folder(name: "CS133")
        context.insert(folder)
        _ = note("rust", in: folder)
        let gone = [note("java", in: folder), note("java", in: folder), note("java", in: folder)]
        try Page.moveToRecentlyDeleted(gone, from: context)

        let page = Page.create(from: .lab, orientation: .portrait, in: folder, context: context)

        let block = try #require(DocumentParser.parse(page.content).compactMap(\.codeBlock).first)
        #expect(block.language == .rust)
    }

    @Test("With no folder, or an empty one, the code block is C++")
    func defaultLanguage() throws {
        let loose = Page.create(from: .lecture, orientation: .portrait, context: context)
        let folder = Folder(name: "Empty")
        context.insert(folder)
        let filed = Page.create(from: .lecture, orientation: .portrait, in: folder, context: context)

        for page in [loose, filed] {
            let block = try #require(DocumentParser.parse(page.content).compactMap(\.codeBlock).first)
            #expect(block.language == .cpp)
        }
    }

    @Test("Every template can be made, and none of them is empty")
    func allMake() {
        for template in NoteTemplate.allCases {
            let page = Page.create(from: template, orientation: .portrait, context: context)
            #expect(page.title == template.title)
            #expect(page.content.count > 40)
        }
    }
}
