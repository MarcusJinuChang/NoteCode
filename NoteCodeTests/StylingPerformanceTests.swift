//
//  StylingPerformanceTests.swift
//  NoteCodeTests
//
//  Styling runs on every keystroke, so its cost is a correctness concern in
//  practice: a slow pass shows up as typing lag, not as a failing assertion.
//  These bounds are deliberately loose — they exist to catch a regression of
//  the order this file was written after (600ms per keystroke), not to police
//  small changes.
//

#if canImport(UIKit)

import Foundation
import Testing
import UIKit
@testable import NoteCode

@Suite("Styling cost")
@MainActor
struct StylingPerformanceTests {

    /// A document shaped like real class notes: prose, headings, lists, and a
    /// code block every twenty-five lines.
    static func document(lines: Int) -> String {
        var out: [String] = []
        for index in 0..<lines {
            switch index % 25 {
            case 0:
                out.append("```cpp")
                out.append("int value\(index) = \(index);")
                out.append("```")
            case 7:
                out.append("- item \(index) with **bold** and `code`")
            case 11:
                out.append("## Heading \(index)")
            default:
                out.append("Line \(index) of prose with *emphasis* in it.")
            }
        }
        return out.joined(separator: "\n")
    }

    private func editor(showing source: String) -> UITextView {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 800, height: 1000)
        textView.text = source
        return textView
    }

    @Test("A full pass over a long document is fast enough to open a page with")
    func fullPassCost() {
        let source = Self.document(lines: 500)
        let textView = editor(showing: source)
        let blocks = DocumentParser.parse(source)

        let start = Date()
        _ = DocumentStyler.applyStyling(to: textView, source: source, blocks: blocks, previousSignatures: [])
        let seconds = Date().timeIntervalSince(start)

        #expect(seconds < 0.1, "full pass over \(blocks.count) blocks took \(seconds)s")
    }

    @Test("A keystroke costs far less than a full pass")
    func keystrokeCost() {
        let source = Self.document(lines: 500)
        let textView = editor(showing: source)
        let signatures = DocumentStyler.applyStyling(
            to: textView,
            source: source,
            blocks: DocumentParser.parse(source),
            previousSignatures: []
        )

        var edited = source
        edited.insert("z", at: edited.index(edited.startIndex, offsetBy: edited.count / 2))
        textView.text = edited
        let blocks = DocumentParser.parse(edited)

        var times: [TimeInterval] = []
        for _ in 0..<5 {
            let start = Date()
            _ = DocumentStyler.applyStyling(
                to: textView,
                source: edited,
                blocks: blocks,
                previousSignatures: signatures
            )
            times.append(Date().timeIntervalSince(start))
        }

        let best = times.min() ?? 0
        #expect(best < 0.02, "keystroke restyle took \(best)s")
    }

    @Test("Parsing is not the expensive part")
    func parseCost() {
        let source = Self.document(lines: 500)

        let start = Date()
        let blocks = DocumentParser.parse(source)
        let seconds = Date().timeIntervalSince(start)

        #expect(blocks.count == 500)
        #expect(seconds < 0.05, "parsing \(source.count) characters took \(seconds)s")
    }
}

// MARK: - Change detection

@Suite("Change detection")
struct ChangedIndicesTests {

    private func signature(_ kind: Int, _ length: Int) -> DocumentStyler.BlockSignature {
        DocumentStyler.BlockSignature(kind: kind, length: length, detail: 0, inlineHash: 0)
    }

    @Test("An unchanged document needs no restyling")
    func nothingChanged() {
        let signatures = [signature(0, 10), signature(0, 20)]
        #expect(DocumentStyler.changedIndices(from: signatures, to: signatures) == nil)
    }

    @Test("Only the edited block is restyled")
    func singleBlockEdit() {
        let old = [signature(0, 10), signature(0, 20), signature(0, 30)]
        var new = old
        new[1] = signature(0, 21)

        #expect(DocumentStyler.changedIndices(from: old, to: new) == 1..<2)
    }

    @Test("An inserted block restyles from the insertion point")
    func insertedBlock() {
        let old = [signature(0, 10), signature(0, 30)]
        let new = [signature(0, 10), signature(0, 20), signature(0, 30)]

        #expect(DocumentStyler.changedIndices(from: old, to: new) == 1..<2)
    }

    @Test("A first pass restyles everything")
    func firstPass() {
        #expect(DocumentStyler.changedIndices(from: [], to: [signature(0, 10)]) == 0..<1)
        #expect(DocumentStyler.changedIndices(from: [], to: []) == nil)
    }

    @Test("A block changing kind is restyled even at the same length")
    func kindChangeAtSameLength() {
        // Typing the third backtick turns prose into code without changing the
        // line's length by more than a character; the kind is what catches it.
        let old = [signature(0, 10)]
        let new = [signature(3, 10)]

        #expect(DocumentStyler.changedIndices(from: old, to: new) == 0..<1)
    }

    @Test("Inline markup changing at the same length is caught")
    func inlineChangeAtSameLength() {
        // `xxbolxx` -> `**bold**`: same kind, same length, different rendering.
        let old = [DocumentStyler.BlockSignature(kind: 0, length: 8, detail: 0, inlineHash: 17)]
        let new = [DocumentStyler.BlockSignature(kind: 0, length: 8, detail: 0, inlineHash: 99)]

        #expect(DocumentStyler.changedIndices(from: old, to: new) == 0..<1)
    }
}

#endif
