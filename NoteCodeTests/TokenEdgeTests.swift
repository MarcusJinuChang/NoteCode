//
//  TokenEdgeTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Foundation
import Testing
import UIKit
@testable import NoteCode

@Suite("Highlighter cost")
@MainActor
struct HighlighterCostTests {

    @Test("Highlighting one block is fast enough to not need much debounce")
    func singleBlockCost() async {
        let code = """
        def compute_average(values):
            total = 0
            for value in values:
                total += value
            return total / len(values)
        """
        let highlighter = HighlightSwiftHighlighter()

        // Warm the JS context; the first call pays for setup.
        _ = await highlighter.colorRuns(for: code, languageTag: "python", appearance: .light)

        var times: [TimeInterval] = []
        for _ in 0..<10 {
            let start = Date()
            _ = await highlighter.colorRuns(for: code, languageTag: "python", appearance: .light)
            times.append(Date().timeIntervalSince(start))
        }

        let worst = times.max() ?? 0

        // The debounce is derived from this number. If highlighting ever gets
        // meaningfully slower, the debounce needs revisiting rather than the
        // symptom being papered over.
        #expect(worst < 0.05, "highlighting one block took \(worst)s")
    }
}

@Suite("Token edges")
@MainActor
struct TokenEdgeTests {

    /// Runs the same pipeline the editor does: style, highlight, paint.
    private func paintedEditor(_ source: String, tag: String) async -> UITextView {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = source

        let blocks = DocumentParser.parse(source)
        DocumentStyler.applyStyling(to: textView, source: source, blocks: blocks)

        guard let code = blocks.compactMap(\.codeBlock).first else { return textView }
        let offset = NSRange(code.contentRange, in: source).location
        let codeText = String(source[code.contentRange])

        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: codeText, languageTag: tag, appearance: .light)

        let painted = runs.map {
            ColorRun(
                range: NSRange(location: offset + $0.range.location, length: $0.range.length),
                color: $0.color
            )
        }
        DocumentStyler.applyColors(
            painted,
            clearing: [NSRange(location: offset, length: (codeText as NSString).length)],
            to: textView
        )
        return textView
    }

    private func colours(_ textView: UITextView, of token: String, in source: String) -> [UIColor?] {
        let range = (source as NSString).range(of: token)
        guard range.location != NSNotFound else { return [] }
        return (0..<range.length).map { index in
            textView.textStorage.attribute(
                .foregroundColor,
                at: range.location + index,
                effectiveRange: nil
            ) as? UIColor
        }
    }

    @Test("Every character of a keyword gets the same colour")
    func keywordFullyColoured() async {
        let source = "```cpp\nint x = 0;\n```"
        let textView = await paintedEditor(source, tag: "cpp")
        let found = colours(textView, of: "int", in: source)

        #expect(found.count == 3)
        #expect(found.first != nil)
        #expect(found.first != UIColor.label, "keyword was not coloured at all")
        #expect(Set(found.map { $0?.description ?? "nil" }).count == 1, "colours across `int` = \(found.map { $0?.description ?? "nil" })")
    }

    @Test("A longer identifier keeps its colour to the last character")
    func longerTokenFullyColoured() async {
        let source = "```py\ndef compute(value):\n    return value\n```"
        let textView = await paintedEditor(source, tag: "py")
        let found = colours(textView, of: "compute", in: source)

        #expect(found.count == 7)
        #expect(Set(found.map { $0?.description ?? "nil" }).count == 1, "colours across `compute` = \(found.map { $0?.description ?? "nil" })")
    }

    @Test("A character typed onto the end of a token keeps the token's colour")
    func typingExtendsTokenColour() async {
        let source = "```cpp\nint x = 0;\n```"
        let textView = await paintedEditor(source, tag: "cpp")

        let ns = source as NSString
        let keyword = ns.range(of: "int")
        let caret = keyword.location + keyword.length
        let keywordColor = textView.textStorage.attribute(.foregroundColor, at: keyword.location, effectiveRange: nil) as? UIColor

        // Put the caret just past `int` and take the attributes the editor
        // would use for the next character typed there.
        textView.selectedRange = NSRange(location: caret, length: 0)
        DocumentStyler.applyTypingAttributes(to: textView, source: source, blocks: DocumentParser.parse(source))

        // Type it.
        textView.textStorage.replaceCharacters(
            in: NSRange(location: caret, length: 0),
            with: NSAttributedString(string: "e", attributes: textView.typingAttributes)
        )

        // The keystroke triggers a restyle before the debounced highlight runs.
        let edited = textView.text ?? ""
        DocumentStyler.applyStyling(to: textView, source: edited, blocks: DocumentParser.parse(edited))

        let typedColor = textView.textStorage.attribute(.foregroundColor, at: caret, effectiveRange: nil) as? UIColor

        #expect(
            typedColor == keywordColor,
            "typed character is \(typedColor?.description ?? "nil") but the token it extends is \(keywordColor?.description ?? "nil")"
        )
    }

    @Test("Colours survive a restyle without losing their last character")
    func coloursSurviveRestyleIntact() async {
        let source = "```cpp\nint x = 0;\n```"
        let textView = await paintedEditor(source, tag: "cpp")

        // A keystroke elsewhere triggers a restyle, which snapshots and
        // reapplies these colours.
        DocumentStyler.applyStyling(to: textView, source: source, blocks: DocumentParser.parse(source))

        let found = colours(textView, of: "int", in: source)
        #expect(Set(found.map { $0?.description ?? "nil" }).count == 1, "after restyle, colours across `int` = \(found.map { $0?.description ?? "nil" })")
    }
}

#endif
