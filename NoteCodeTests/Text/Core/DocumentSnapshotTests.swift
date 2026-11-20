//
//  DocumentSnapshotTests.swift
//  NoteCodeTests
//
//  The snapshot answers what the readers it will replace answer today:
//  DocumentParser, DocumentStyler.layouts, DocumentCache.codeRanges and
//  MarkdownLayout.runs; targets and newlines are checked against the text.
//

import Foundation
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import NoteCode

@Suite("DocumentSnapshot", .tags(.pure))
struct DocumentSnapshotTests {

    /// Text with é and an emoji ahead of the code, so UTF-8 and UTF-16
    /// offsets differ; closed, output, bare and unclosed blocks.
    static let notes: [String] = [
        "",
        "plain\n",
        "# Héad 🎉\n\nsome *text* é\n\n```cpp\nint x = 1;\n```\n\nmore **bold**\n\n```\nbare\n```\n- [ ] item\n\n```output\nok\n```\n```python\nprint(1)",
        "```java\nclass A {}\n```",
        "```cpp\nno newline after the close\n```\nnext",
    ]

    @Test("The same parse and layouts as calling them directly", arguments: notes)
    func matchesParserAndLayouts(_ text: String) {
        let snapshot = DocumentSnapshot(text: text)
        #expect(snapshot.source == text)
        let parsed = DocumentParser.parse(text)
        #expect(snapshot.blocks.count == parsed.count)
        let direct = DocumentStyler.layouts(for: parsed, in: text)
        #expect(snapshot.layouts.map(\.range) == direct.map(\.range))
        #expect(snapshot.layouts.map(\.signature) == direct.map(\.signature))
    }

    @Test("The same code ranges as DocumentCache", arguments: notes)
    func matchesCodeRanges(_ text: String) {
        #expect(DocumentSnapshot(text: text).codeRanges == DocumentCache().codeRanges(for: text))
    }

    @Test("The same marker runs as MarkdownLayout", arguments: notes)
    func matchesMarkerRuns(_ text: String) {
        #expect(DocumentSnapshot(text: text).markerRuns == MarkdownLayout.runs(for: DocumentParser.parse(text), in: text))
    }

    @Test("Targets cover the code ranges, and hold each block's own text", arguments: notes)
    func targetsMatchCodeRanges(_ text: String) {
        let snapshot = DocumentSnapshot(text: text)
        #expect(snapshot.targets.map(\.range) == snapshot.codeRanges.map(\.range))
        let ns = text as NSString
        for target in snapshot.targets {
            #expect(ns.substring(with: target.range).contains(target.code))
        }
    }

    @Test("A code block's newlines are the UTF-16 offsets of its \\n", arguments: notes)
    func newlinesMatchSearch(_ text: String) {
        let snapshot = DocumentSnapshot(text: text)
        let ns = text as NSString
        for (index, code) in snapshot.codeRanges.enumerated() {
            var expected: [Int] = []
            for offset in code.range.location..<NSMaxRange(code.range) where ns.character(at: offset) == 10 {
                expected.append(offset)
            }
            #expect(snapshot.newlines(ofCodeBlock: index) == expected)
        }
    }

    @Test("A bridged string is converted once, on the way in")
    func convertsOnInit() throws {
        #if canImport(UIKit)
        let storage = NSTextStorage(string: String(repeating: "int x = 1; // é\n", count: 200))
        let bridged = storage.string
        try #require(!bridged.isContiguousUTF8, "the premise: the text view's string is bridged")
        let snapshot = DocumentSnapshot(text: bridged, editCount: 7)
        #expect(snapshot.source.isContiguousUTF8)
        #expect(snapshot.source == bridged)
        #expect(snapshot.editCount == 7)
        #endif
    }

    @Test("An unclosed block runs to the end and its last caret is the end")
    func unclosed() {
        let text = Self.notes[2]
        let last = DocumentSnapshot(text: text).codeRanges.last
        #expect(last?.isClosed == false)
        #expect(last?.lastCaret == text.utf16.count)
    }
}
