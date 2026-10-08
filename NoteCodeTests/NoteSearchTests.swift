//
//  NoteSearchTests.swift
//  NoteCodeTests
//

import Foundation
import SwiftData
import Testing
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
@testable import NoteCode

@Suite("Note search")
struct NoteSearchTests {

    // MARK: What matches

    @Test("An empty search matches nothing, and the list shows as it is")
    func emptySearch() {
        #expect(NoteSearch("").isEmpty)
        #expect(NoteSearch("  \n ").isEmpty)
        #expect(NoteSearch(" ").match(title: "Anything", content: "at all") == nil)
    }

    @Test("Every word has to appear, in the title or the text, in any order")
    func everyWord() {
        let search = NoteSearch("search binary")
        #expect(search.terms == ["search", "binary"])

        #expect(search.match(title: "Binary trees", content: "Depth-first search") != nil)
        #expect(search.match(title: "Lecture 4", content: "binary search on a sorted array") != nil)
        #expect(search.match(title: "Binary trees", content: "Inorder traversal") == nil)
    }

    @Test("Case, accents and word boundaries don't matter")
    func loose() {
        #expect(NoteSearch("cafe").match(title: "Café notes", content: "") != nil)
        #expect(NoteSearch("VECTOR").match(title: "", content: "std::vector<int>") != nil)
        #expect(NoteSearch("vec").match(title: "", content: "std::vector<int>") != nil)
        #expect(NoteSearch("Ünïcode").match(title: "", content: "unicode strings") != nil)
    }

    @Test("A note is a title match only when every word is in its title")
    func titleMatch() {
        let search = NoteSearch("binary search")
        #expect(search.match(title: "Binary search", content: "")?.inTitle == true)
        #expect(search.match(title: "Binary trees", content: "search")?.inTitle == false)
    }

    // MARK: Excerpts

    @Test("The excerpt is the line holding the text's first match, trimmed")
    func excerptLine() {
        let content = "# Lecture 4\n\n  The loop invariant holds.  \nThen a second invariant.\n"
        #expect(NoteSearch("invariant").match(title: "", content: content)?.excerpt == "The loop invariant holds.")
    }

    @Test("The excerpt comes from whichever word matches first in the text")
    func excerptFirstWord() {
        let content = "Heaps come first.\nThen sorting.\nThen heaps again."
        #expect(NoteSearch("sorting heaps").match(title: "", content: content)?.excerpt == "Heaps come first.")
    }

    @Test("Only a title match has no excerpt")
    func excerptTitleOnly() {
        let match = NoteSearch("graphs").match(title: "Graphs", content: "BFS and DFS")
        #expect(match != nil)
        #expect(match?.excerpt == nil)
    }

    @Test("Far along a long line, the excerpt starts near the match, at a word")
    func excerptLongLine() throws {
        let content = "Before the match there is a long run of words that would push it out of the row entirely, and then pivot comes."
        let excerpt = try #require(NoteSearch("pivot").match(title: "", content: content)?.excerpt)

        #expect(excerpt.hasPrefix("…"))
        #expect(excerpt.hasSuffix("then pivot comes."))
        // At a word: the character after the ellipsis starts one.
        let afterEllipsis = excerpt.dropFirst()
        let start = content.range(of: String(afterEllipsis))
        #expect(start != nil)
        if let start {
            #expect(start.lowerBound == content.startIndex || content[content.index(before: start.lowerBound)] == " ")
        }
        #expect(afterEllipsis.count <= NoteSearch.excerptLead + "pivot comes.".count)
    }

    // MARK: Matches in the text

    @Test("Matches are every occurrence of every word, in order, in UTF-16")
    func matchesInText() {
        let content = "🙂 loop, then Loop again; a lööp"
        let matches = NoteSearch("loop").matches(in: content)
        let ns = content as NSString

        #expect(matches.map { ns.substring(with: $0) } == ["loop", "Loop", "lööp"])
        // The emoji is two UTF-16 units: the first match starts at 3, not 2.
        #expect(matches.first?.location == 3)
    }

    @Test("Overlapping words are one match")
    func overlappingMatches() {
        let content = "vector and vec"
        let matches = NoteSearch("vec vector").matches(in: content)
        #expect(matches.map { (content as NSString).substring(with: $0) } == ["vector", "vec"])
    }

    @Test("Matches stop at the limit")
    func matchLimit() {
        let content = String(repeating: "a ", count: 1_000)
        #expect(NoteSearch("a").matches(in: content, limit: 20).count == 20)
    }

    // MARK: Bold

    @Test("The words searched for are bold in a result's title and excerpt")
    func highlighted() {
        let text = NoteSearch("loop inv").highlighted("The loop invariant holds")
        let bold = text.runs
            .filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(text[$0.range].characters) }

        #expect(bold == ["loop", "inv"])
        #expect(String(text.characters) == "The loop invariant holds")
    }
}

// MARK: - Results

@Suite("Note search results")
@MainActor
struct NoteSearchResultsTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func note(_ title: String, _ content: String = "", modified day: Int = 0) -> Page {
        let page = Page(title: title, content: content)
        page.modifiedAt = Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
        context.insert(page)
        return page
    }

    @Test("Title matches come first, then the rest, each in the reader's sort")
    func order() {
        let oldTitle = note("Heaps", modified: 1)
        let newTitle = note("Heaps and stacks", modified: 5)
        let oldText = note("Lecture 3", "heaps", modified: 2)
        let newText = note("Lecture 9", "a heap of heaps", modified: 9)
        _ = note("Graphs", "BFS", modified: 10)

        let results = NoteSearch("heaps").results(in: context.allPages, sort: .default)

        #expect(results.map(\.page.title) == [newTitle, oldTitle, newText, oldText].map(\.title))
    }

    @Test("Notes in folders and pinned notes are results like any other")
    func flat() {
        let folder = Folder(name: "CS 133")
        context.insert(folder)
        let filed = note("Pointers", "nullptr")
        filed.folder = folder
        let pinned = note("Pinned", "nullptr")
        pinned.isPinned = true

        let results = NoteSearch("nullptr").results(in: context.allPages, sort: .default)

        #expect(Set(results.map(\.page.title)) == ["Pointers", "Pinned"])
    }
}

private extension ModelContext {
    var allPages: [Page] {
        (try? fetch(FetchDescriptor<Page>())) ?? []
    }
}

// MARK: - Opening a result

#if canImport(UIKit)

@Suite("Opening a search result")
@MainActor
struct SearchRevealTests {

    /// Enough pages that the match is well below the first screen.
    private static let text = (0..<300)
        .map { $0 == 240 ? "Line \($0): the needle is here." : "Line \($0): an invariant holds before and after every iteration." }
        .joined(separator: "\n")

    @Test("The page scrolls to the first match once it's laid out")
    func scrollsToMatch() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 1200))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = Self.text
        let page = PageView(textView: textView)

        let matches = NoteSearch("needle").matches(in: Self.text)
        let first = try #require(matches.first)
        page.reveal(first, highlighting: matches)

        page.frame = CGRect(x: 0, y: 0, width: 880, height: 1100)
        window.addSubview(page)
        window.makeKeyAndVisible()
        page.layoutIfNeeded()
        textView.layoutIfNeeded()
        // The reveal runs after the layout pass that finds the page sized.
        try await Task.sleep(for: .milliseconds(100))

        let top = try #require(page.lineTop(atCharacter: first.location))
        let visible = textView.contentOffset.y..<(textView.contentOffset.y + textView.bounds.height)
        #expect(textView.contentOffset.y > 0)
        #expect(visible.contains(top))
    }

    @Test("Highlights come and go with the search result's matches")
    func highlights() {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = "the needle"

        #expect(!textView.showsSearchMatches)

        let needle = NSRange(location: 4, length: 6)
        textView.highlightSearchMatches([needle], current: needle)
        #expect(textView.showsSearchMatches)

        textView.clearSearchHighlights()
        #expect(!textView.showsSearchMatches)
    }

    @Test("Typing in the editor takes a search result's highlights away")
    func typingClearsHighlights() {
        final class Box { var value = "" }
        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.text = "the needle"

        let needle = NSRange(location: 4, length: 6)
        textView.highlightSearchMatches([needle], current: needle)
        coordinator.textViewDidChange(textView)

        #expect(!textView.showsSearchMatches)
    }
}

#endif
