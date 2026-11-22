//
//  TestNotesTests.swift
//  NoteCodeTests
//
//  The test set Settings › Help and About › Add Test Notes makes.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Test notes", .tags(.library))
@MainActor
struct TestNotesTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    @Test("Every note but the empty one opens with its checklist")
    func checklists() {
        for note in TestNotes.all where !note.content.isEmpty {
            #expect(note.content.contains("## What to check\n\n- [ ] "), "\(note.title)")
        }
    }

    @Test("Titles are unique, and each note's first heading is its title")
    func titles() {
        let titles = TestNotes.all.map(\.title)
        #expect(Set(titles).count == titles.count)
        for note in TestNotes.all where !note.content.isEmpty {
            #expect(note.content.hasPrefix("# \(note.title)\n"), "\(note.title)")
        }
    }

    @Test("The code note has a closed block in every language")
    func everyLanguage() throws {
        let blocks = DocumentParser.parse(TestNotes.code).compactMap(\.codeBlock)
        for language in CodeLanguage.allCases {
            #expect(blocks.contains { $0.language == language && $0.isClosed }, "\(language)")
        }
        #expect(blocks.contains { $0.language == nil && !$0.isOutput })
        #expect(blocks.contains { $0.isOutput })
        #expect(blocks.allSatisfy { $0.isClosed })
    }

    @Test("Only the edge cases end in an unclosed fence")
    func unclosedFence() {
        for note in TestNotes.all {
            let open = DocumentParser.parse(note.content).compactMap(\.codeBlock).filter { !$0.isClosed }
            #expect(open.count == (note.title == "Test 8 · Edge cases" ? 1 : 0), "\(note.title)")
        }
    }

    @Test("Every display formula in the formula note draws")
    func displayFormulas() {
        let content = TestNotes.formulas
        let blocks = DocumentParser.parse(content).compactMap { block -> String? in
            if case .math(let math) = block.kind { return String(content[math.contentRange]) }
            return nil
        }
        #expect(blocks.count >= 6)
        for tex in blocks {
            #expect(FormulaValidity.compute(tex).isValid, "\(tex)")
        }
    }

    @Test("The long note runs to many pages' worth of lines")
    func longNote() {
        let lines = TestNotes.long.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count > 250)
        #expect(TestNotes.long.contains("Line 200"))
    }

    @Test("Adding makes the folder, its inner folder and every note")
    func adds() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let folder = TestNotes.add(to: context, now: now)
        try context.save()

        #expect(folder.name == TestNotes.folderName)
        let inner = try #require(folder.subfolders?.first)
        #expect(inner.name == TestNotes.nestedFolderName)

        let pages = try context.fetch(FetchDescriptor<Page>())
        #expect(pages.count == TestNotes.all.count)
        for note in TestNotes.all {
            let page = try #require(pages.first { $0.title == note.title })
            #expect(page.content == note.content)
            #expect(page.orientation == note.orientation)
            #expect(page.isTextLocked == note.isTextLocked)
            #expect(page.folder === (note.isNested ? inner : folder))
            #expect(page.isLive)
        }

        // Newest first is the numbered order.
        let byDate = pages.sorted { $0.modifiedAt > $1.modifiedAt }.map(\.title)
        #expect(byDate == TestNotes.all.map(\.title))
    }

    @Test("Adding again makes a second set beside the first")
    func addsTwice() throws {
        TestNotes.add(to: context)
        TestNotes.add(to: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Page>()) == 2 * TestNotes.all.count)
    }
}
