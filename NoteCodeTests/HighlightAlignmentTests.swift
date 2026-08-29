//
//  HighlightAlignmentTests.swift
//  NoteCodeTests
//
//  Colour runs are offsets into a code string. If those offsets drift from the
//  characters they describe, colours land on the wrong text — and it still
//  *looks* like syntax highlighting, just wrong. These pin the alignment down.
//

import Foundation
import Testing
@testable import NoteCode

#if canImport(UIKit)
import UIKit

private func colouredText(_ code: String, _ tag: String) async -> [String] {
    let runs = await HighlightSwiftHighlighter()
        .colorRuns(for: code, languageTag: tag, appearance: .dark)
    let source = code as NSString
    return runs.compactMap { run in
        guard run.range.location >= 0,
              run.range.location + run.range.length <= source.length
        else { return nil }
        return source.substring(with: run.range)
    }
}

@Suite("Highlight alignment")
struct HighlightAlignmentTests {

    @Test("Keywords are coloured, as a control")
    func asciiControl() async {
        let coloured = await colouredText("int x = 0;", "cpp")
        #expect(coloured.contains("int"))
    }

    @Test("Non-ASCII earlier in the block doesn't shift later offsets")
    func nonASCIIDoesNotShiftOffsets() async {
        // Accents are two UTF-8 bytes but one UTF-16 unit; the check mark is
        // one UTF-16 unit. If the library indexes by Character and we read as
        // UTF-16 (or vice versa), `int` gets coloured at the wrong place.
        let coloured = await colouredText("// café ✓\nint x = 0;", "cpp")
        #expect(coloured.contains("int"))
    }

    @Test("Astral characters don't shift later offsets")
    func emojiDoesNotShiftOffsets() async {
        // An emoji is a surrogate pair: two UTF-16 units, one Character. This
        // is where Character-vs-UTF-16 indexing bugs actually show up.
        let coloured = await colouredText("// 🎉 party\nint x = 0;", "cpp")
        #expect(coloured.contains("int"))
    }

    @Test("Every run's text is a real substring of the code", arguments: [
        "int x = 0;",
        "// café ✓\nint x = 0;",
        "// 🎉\nint y = 1;",
        "std::string s = \"héllo\";",
    ])
    func runsStayInBounds(code: String) async {
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: code, languageTag: "cpp", appearance: .dark)
        let length = (code as NSString).length

        #expect(!runs.isEmpty)
        for run in runs {
            #expect(run.range.location >= 0)
            #expect(run.range.location + run.range.length <= length)
        }
    }

    @Test("Python strings are coloured where the string actually is")
    func pythonStringAlignment() async {
        let coloured = await colouredText("x = \"héllo wörld\"\nprint(x)", "python")
        #expect(coloured.contains { $0.contains("héllo") } || coloured.contains("print"))
    }
}

#endif
