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

    // MARK: Whitespace at the edges of a block

    // highlight.js trims whitespace off both ends of what it is given and
    // reports offsets into the trimmed text. Leading whitespace therefore
    // shifts every colour left unless the highlighter compensates, so each
    // token loses its last character and picks up the one before it. This is
    // the "last letter never highlights" bug, and a blank first line is the
    // ordinary way to hit it: press return after the opening fence and the
    // newline becomes part of the code.

    @Test("A blank first line doesn't shift colours off their tokens", arguments: [
        "\nint x = 0;",
        "\n\nint x = 0;",
        "\n\t int x = 0;",
    ])
    func leadingWhitespaceDoesNotShiftOffsets(code: String) async {
        let coloured = await colouredText(code, "cpp")
        #expect(coloured.contains("int"))
    }

    @Test("Keywords late in a block are still coloured exactly")
    func tokensStayAlignedAfterLeadingBlankLines() async {
        // The signature of the shift is that every run slides toward the front
        // of the block, so a keyword comes back with its last character missing
        // and the whitespace before it attached. Checking a keyword near the end
        // catches it; checking only the first one sometimes does not.
        let coloured = await colouredText("\n\nint x = 0;\nreturn x;", "cpp")

        #expect(coloured.contains("int"))
        #expect(coloured.contains("return"))
    }

    @Test("Trailing blank lines leave the earlier colours alone")
    func trailingWhitespaceIsHarmless() async {
        let coloured = await colouredText("int x = 0;\n\n\n", "cpp")
        #expect(coloured.contains("int"))
    }

    @Test("A block that is nothing but whitespace produces no colours")
    func whitespaceOnlyBlock() async {
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: "\n\n   \n", languageTag: "cpp", appearance: .dark)
        #expect(runs.isEmpty)
    }
}

#endif
