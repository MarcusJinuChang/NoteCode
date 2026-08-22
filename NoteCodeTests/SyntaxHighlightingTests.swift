//
//  SyntaxHighlightingTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

// MARK: - Appearance

@Suite("Highlight appearance")
@MainActor
struct HighlightAppearanceTests {

    @Test("Appearance follows the trait collection")
    func fromTraits() {
        #expect(HighlightAppearance(UITraitCollection(userInterfaceStyle: .dark)) == .dark)
        #expect(HighlightAppearance(UITraitCollection(userInterfaceStyle: .light)) == .light)
        #expect(HighlightAppearance(UITraitCollection(userInterfaceStyle: .unspecified)) == .light)
    }
}

// MARK: - The highlighter

@Suite("HighlightSwift adapter")
struct HighlightSwiftHighlighterTests {

    @Test("Every supported language produces colours", arguments: [
        (CodeLanguage.cpp, "int x = 0;"),
        (CodeLanguage.java, "class A { int x = 0; }"),
        (CodeLanguage.python, "print(\"hi\")"),
    ])
    func producesColors(language: CodeLanguage, code: String) async {
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: code, language: language, appearance: .dark)

        // Guards the scope bug this was written after: HighlightSwift populates
        // the UIKit attribute scope, and reading the SwiftUI one returned no
        // colours at all while everything else looked like it worked.
        #expect(!runs.isEmpty)
    }

    @Test("Empty code produces no runs")
    func emptyCode() async {
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: "", language: .cpp, appearance: .dark)

        #expect(runs.isEmpty)
    }

    @Test("Run ranges stay inside the code they describe")
    func runsStayInBounds() async {
        let code = "int lo = 0;\nint hi = n - 1;"
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: code, language: .cpp, appearance: .dark)
        let length = (code as NSString).length

        #expect(!runs.isEmpty)
        for run in runs {
            #expect(run.range.location >= 0)
            #expect(run.range.location + run.range.length <= length)
        }
    }

    @Test("Light and dark produce different colours")
    func appearanceChangesColors() async {
        let highlighter = HighlightSwiftHighlighter()
        let code = "int x = 0;"

        let light = await highlighter.colorRuns(for: code, language: .cpp, appearance: .light)
        let dark = await highlighter.colorRuns(for: code, language: .cpp, appearance: .dark)

        #expect(!light.isEmpty)
        #expect(!dark.isEmpty)
        #expect(light != dark)
    }
}

// MARK: - Applying colours

@Suite("Applying colours")
@MainActor
struct ApplyColorsTests {

    private static let source = "prose\n```cpp\nint x;\n```\n"
    private static let codeOffset = ("prose\n```cpp\n" as NSString).length

    private func styledTextView() -> UITextView {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = Self.source
        DocumentStyler.applyStyling(to: textView)
        return textView
    }

    @Test("Colours land without disturbing the monospace font")
    func colorsPreserveFont() {
        let textView = styledTextView()
        let range = NSRange(location: Self.codeOffset, length: 3)

        DocumentStyler.applyColors([ColorRun(range: range, color: .systemRed)], to: textView)

        let storage = textView.textStorage
        #expect(storage.attribute(.font, at: Self.codeOffset, effectiveRange: nil) as? UIFont == DocumentStyler.codeFont)
        #expect(storage.attribute(.foregroundColor, at: Self.codeOffset, effectiveRange: nil) as? UIColor == .systemRed)
    }

    @Test("Out-of-bounds runs are skipped rather than trapping")
    func outOfBoundsRunsIgnored() {
        let textView = styledTextView()
        let length = textView.textStorage.length

        // These describe a document that has since been edited down.
        DocumentStyler.applyColors(
            [
                ColorRun(range: NSRange(location: length + 50, length: 5), color: .systemRed),
                ColorRun(range: NSRange(location: length - 1, length: 99), color: .systemRed),
                ColorRun(range: NSRange(location: -1, length: 3), color: .systemRed),
            ],
            to: textView
        )

        // Reaching here at all is the assertion — a bad range would have trapped.
        #expect(textView.textStorage.length == length)
    }

    @Test("A restyle clears previously applied colours")
    func restyleResetsColors() {
        let textView = styledTextView()
        let range = NSRange(location: Self.codeOffset, length: 3)

        DocumentStyler.applyColors([ColorRun(range: range, color: .systemRed)], to: textView)
        #expect(textView.textStorage.attribute(.foregroundColor, at: Self.codeOffset, effectiveRange: nil) as? UIColor == .systemRed)

        // Styling resets foregrounds to .label, which is what lets stale colours
        // disappear when the document changes.
        DocumentStyler.applyStyling(to: textView)
        #expect(textView.textStorage.attribute(.foregroundColor, at: Self.codeOffset, effectiveRange: nil) as? UIColor == .label)
    }
}

#endif
