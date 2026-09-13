//
//  SyntaxHighlightingTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
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

    @Test("The runnable languages produce colours", arguments: [
        ("cpp", "int x = 0;"),
        ("java", "class A { int x = 0; }"),
        ("python", "print(\"hi\")"),
    ])
    func producesColors(tag: String, code: String) async {
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: code, languageTag: tag, appearance: .dark)

        // Guards the scope bug this was written after: HighlightSwift populates
        // the UIKit attribute scope, and reading the SwiftUI one returned no
        // colours at all while everything else looked like it worked.
        #expect(!runs.isEmpty)
    }

    @Test("Empty code produces no runs")
    func emptyCode() async {
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: "", languageTag: "cpp", appearance: .dark)

        #expect(runs.isEmpty)
    }

    @Test("Languages NoteCode can't run are still coloured", arguments: [
        ("rust", "fn main() { let y = 1; }"),
        ("swift", "let x = 0"),
        ("javascript", "const x = 0;"),
        ("sql", "SELECT * FROM t;"),
        ("go", "func main() {}"),
    ])
    func colorsBeyondTheRunnableLanguages(tag: String, code: String) async {
        // Highlighting used to be gated on CodeLanguage, which lists only what
        // Piston can execute — so every other language silently rendered plain
        // with nothing to indicate why.
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: code, languageTag: tag, appearance: .dark)

        #expect(!runs.isEmpty)
    }

    @Test("An untagged or unrecognized fence stays plain", arguments: ["", "notalanguage"])
    func unknownTagsStayPlain(tag: String) async {
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: "int x = 0;", languageTag: tag, appearance: .dark)

        #expect(runs.isEmpty)
    }

    @Test("Run ranges stay inside the code they describe")
    func runsStayInBounds() async {
        let code = "int lo = 0;\nint hi = n - 1;"
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: code, languageTag: "cpp", appearance: .dark)
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

        let light = await highlighter.colorRuns(for: code, languageTag: "cpp", appearance: .light)
        let dark = await highlighter.colorRuns(for: code, languageTag: "cpp", appearance: .dark)

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

        DocumentStyler.applyColors([ColorRun(range: range, color: .systemRed)], clearing: [], to: textView)

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
            clearing: [NSRange(location: length + 500, length: 5)],
            to: textView
        )

        // Reaching here at all is the assertion — a bad range would have trapped.
        #expect(textView.textStorage.length == length)
    }

    @Test("A restyle keeps colours already applied to code")
    func restyleKeepsCodeColors() {
        let textView = styledTextView()
        let range = NSRange(location: Self.codeOffset, length: 3)

        DocumentStyler.applyColors([ColorRun(range: range, color: .systemRed)], clearing: [], to: textView)
        #expect(textView.textStorage.attribute(.foregroundColor, at: Self.codeOffset, effectiveRange: nil) as? UIColor == .systemRed)

        // This assertion used to be the opposite. Restyling runs on every
        // keystroke and highlighting is async, so wiping colours here left the
        // whole document uncoloured for as long as the user kept typing.
        DocumentStyler.applyStyling(to: textView)
        #expect(textView.textStorage.attribute(.foregroundColor, at: Self.codeOffset, effectiveRange: nil) as? UIColor == .systemRed)
    }

    @Test("Colours outside a code block are not carried over")
    func proseColoursAreNotPreserved() {
        let textView = styledTextView()

        // Prose has no business holding syntax colours; only code blocks do.
        textView.textStorage.addAttribute(.foregroundColor, value: UIColor.systemRed, range: NSRange(location: 0, length: 3))
        DocumentStyler.applyStyling(to: textView)

        #expect(textView.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == .label)
    }

    @Test("A fresh highlight pass clears the block before painting")
    func newPassClearsStaleColours() {
        let textView = styledTextView()
        let codeRange = NSRange(location: Self.codeOffset, length: 6)

        DocumentStyler.applyColors([ColorRun(range: codeRange, color: .systemRed)], clearing: [], to: textView)

        // A later pass covering the same block with no runs — what a changed
        // language tag produces — must not leave the old colours behind.
        DocumentStyler.applyColors([], clearing: [codeRange], to: textView)

        #expect(textView.textStorage.attribute(.foregroundColor, at: Self.codeOffset, effectiveRange: nil) as? UIColor == .label)
    }
}

// MARK: - Switching appearance

@Suite("Highlighting follows an appearance switch")
@MainActor
struct AppearanceSwitchTests {

    /// Keywords, a string literal and plain identifiers, so every kind of
    /// token the theme colours is covered.
    private static let code = "int count = 0;\nstd::string name = \"hi\";\nreturn count;"
    private static let source = "prose\n```cpp\n\(code)\n```\n"
    private static let codeOffset = ("prose\n```cpp\n" as NSString).length

    @Test("Code coloured under dark is re-coloured when the view turns light")
    func darkToLight() async {
        await expectRecolouring(from: .dark, to: .light)
    }

    @Test("Code coloured under light is re-coloured when the view turns dark")
    func lightToDark() async {
        await expectRecolouring(from: .light, to: .dark)
    }

    /// Goes through the coordinator rather than DocumentStyler, because the
    /// bug lived there: blocks were remembered as coloured by content alone,
    /// so an unchanged block was never highlighted again.
    private func expectRecolouring(from before: HighlightAppearance, to after: HighlightAppearance) async {
        let highlighter = HighlightSwiftHighlighter()
        let beforeRuns = await highlighter.colorRuns(for: Self.code, languageTag: "cpp", appearance: before)
        let afterRuns = await highlighter.colorRuns(for: Self.code, languageTag: "cpp", appearance: after)

        // Without a difference between the themes this test proves nothing.
        #expect(!beforeRuns.isEmpty)
        #expect(beforeRuns.first?.color != afterRuns.first?.color)

        let textView = DocumentTextView.makeConfiguredTextView()
        textView.traitOverrides.userInterfaceStyle = Self.style(before)
        textView.updateTraitsIfNeeded()

        let coordinator = DocumentTextView.Coordinator(text: .constant(Self.source))
        textView.delegate = coordinator
        coordinator.observeAppearance(of: textView)
        textView.text = Self.source
        coordinator.invalidateStyling()
        coordinator.restyle(textView)

        let unpaintedBefore = await Self.waitUntilPainted(beforeRuns, in: textView)
        #expect(unpaintedBefore.isEmpty, "never coloured for \(before) to begin with")

        textView.traitOverrides.userInterfaceStyle = Self.style(after)
        textView.updateTraitsIfNeeded()

        let unpaintedAfter = await Self.waitUntilPainted(afterRuns, in: textView)
        #expect(unpaintedAfter.isEmpty, "\(unpaintedAfter.count) of \(afterRuns.count) runs kept the \(before) colours")
    }

    private static func style(_ appearance: HighlightAppearance) -> UIUserInterfaceStyle {
        appearance == .dark ? .dark : .light
    }

    /// Polls until every run's colour is in the text storage, since
    /// highlighting is debounced and runs off the main actor. Returns the runs
    /// still wrong when time runs out.
    private static func waitUntilPainted(_ runs: [ColorRun], in textView: UITextView) async -> [ColorRun] {
        let deadline = ContinuousClock.now + .seconds(3)

        while true {
            let unpainted = runs.filter { run in
                guard run.range.length > 0 else { return false }
                let color = textView.textStorage.attribute(
                    .foregroundColor, at: codeOffset + run.range.location, effectiveRange: nil
                ) as? UIColor
                return color != run.color
            }
            if unpainted.isEmpty || ContinuousClock.now >= deadline {
                return unpainted
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

#endif
