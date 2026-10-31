//
//  NoteTitleTests.swift
//  NoteCodeTests
//
//  A note nobody has named is called by its first line.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Note titles")
struct NoteTitleTests {

    @Test("A heading names the note, without its #")
    func heading() {
        #expect(NoteTitle.derived(from: "# CS133 Lecture 5\n\nBody") == "CS133 Lecture 5")
        #expect(NoteTitle.derived(from: "### Third level") == "Third level")
    }

    @Test("Markers are left out: bold, code, links, bullets, quotes")
    func markers() {
        #expect(NoteTitle.derived(from: "## **Big-O** and `std::sort`") == "Big-O and std::sort")
        #expect(NoteTitle.derived(from: "See [the notes](https://example.com) now") == "See the notes now")
        #expect(NoteTitle.derived(from: "- first item") == "first item")
        #expect(NoteTitle.derived(from: "> quoted") == "quoted")
    }

    @Test("Blank lines, fences and code are passed over")
    func passesOver() {
        #expect(NoteTitle.derived(from: "\n\n   \n# After blanks") == "After blanks")
        #expect(NoteTitle.derived(from: "```cpp\n# not a heading\nint x;\n```\nThen prose") == "Then prose")
        #expect(NoteTitle.derived(from: "```cpp\nint x;") == nil, "an open fence runs to the end")
    }

    @Test("A long first line is cut with an ellipsis")
    func cut() throws {
        let long = String(repeating: "word ", count: 40)
        let title = try #require(NoteTitle.derived(from: long))
        #expect(title.count <= NoteTitle.limit + 1)
        #expect(title.hasSuffix("…"))
    }

    @Test("Reading a huge note costs the start of it, and finds nothing past the scan")
    func bounded() {
        let huge = String(repeating: "```\ncode\n```\n", count: 50_000) + "# Far away"
        #expect(NoteTitle.derived(from: huge) == nil)
    }

    @Test("A name the reader gave wins; Untitled with text takes the first line; empty stays Untitled")
    func display() {
        #expect(NoteTitle.display(stored: "Lab 2", content: "# Other") == "Lab 2")
        #expect(NoteTitle.display(stored: "Untitled", content: "# CS133 Lecture 5") == "CS133 Lecture 5")
        #expect(NoteTitle.display(stored: "Untitled", content: "") == "Untitled")
        #expect(NoteTitle.display(stored: "Untitled", content: " \n\n") == "Untitled")
        #expect(NoteTitle.display(stored: "  ", content: "Hello") == "Hello")
    }

    @Test("A page shows its first line, follows edits, and renaming stores a name")
    func page() {
        let page = Page(content: "# CS133 Lecture 5\nbody")
        #expect(page.title == "Untitled", "stored as it always was")
        #expect(page.displayTitle == "CS133 Lecture 5")

        page.content = "# Lecture 6"
        #expect(page.displayTitle == "Lecture 6")

        page.rename(to: "Lecture 6")
        #expect(page.title == "Untitled", "the field opened and closed unchanged: nothing is frozen")

        page.rename(to: "  My name ")
        #expect(page.title == "My name")
        page.content = "# Something else"
        #expect(page.displayTitle == "My name")

        page.rename(to: "   ")
        #expect(page.title == "Untitled")
        #expect(page.displayTitle == "Something else", "a cleared name goes back to the first line")
    }

    @Test("Duplicate copies the shown title")
    func duplicate() throws {
        let container = try ModelContainer(for: Schema([Page.self, Folder.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let page = Page(content: "# Heaps")
        context.insert(page)
        #expect(page.duplicated(in: context).title == "Heaps copy")
    }

    @Test("Export names an unnamed note by its first line")
    func fileName() {
        let page = Page(content: "# CS133 Lecture 5")
        #expect(NotePDF.fileName(for: page.displayTitle) == "CS133 Lecture 5.pdf")
    }
}
