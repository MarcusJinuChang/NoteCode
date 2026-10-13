//
//  OutputBlockTests.swift
//  NoteCodeTests
//
//  v3 phase 4: ```output, a console panel with Copy and no Run.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Output blocks")
@MainActor
struct OutputBlockTests {

    private static let note = "Before\n```cpp\nint main() {}\n```\n```output\nbefore: 1 -> 2 -> 3\nafter:  3 -> 2 -> 1\n```\nAfter\n"

    // MARK: The model

    @Test("Output is the first word of the info string, in any case, and not a language")
    func parsing() throws {
        for (source, expected) in [
            ("```output\nx\n```", true), ("```Output\nx\n```", true), ("```OUTPUT\nx\n```", true),
            ("```output stdout\nx\n```", true),
            ("```outputs\nx\n```", false), ("```cpp output\nx\n```", false), ("```\nx\n```", false),
        ] {
            let block = try #require(DocumentParser.parse(source).first?.codeBlock)
            #expect(block.isOutput == expected, "\(source)")
            if block.isOutput { #expect(block.language == nil) }
        }
    }

    @Test("An output target has Copy and no Run, says Output, and ticks Output")
    func target() throws {
        let source = Self.note
        let targets = CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source))
        #expect(targets.count == 2)
        #expect(targets[0].kind == .language(.cpp))
        #expect(targets[0].canRun)
        #expect(!targets[0].isOutput)

        let output = targets[1]
        #expect(output.isOutput)
        #expect(!output.canRun)
        #expect(output.languageLabel == "Output")
        #expect(output.kind == .output)
        #expect(output.code == "before: 1 -> 2 -> 3\nafter:  3 -> 2 -> 1\n")
    }

    @Test("Kinds: plain is a bare fence, and a tag the app doesn't know is none of them")
    func kinds() throws {
        func kind(_ source: String) throws -> CodeBlockKind? {
            try #require(CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source)).first).kind
        }
        #expect(try kind("```\nx\n```") == .plain)
        #expect(try kind("```ruby\nx\n```") == nil)
        #expect(try kind("```sql\nx\n```") == .language(.sql))
    }

    @Test("SQL has Copy and no Run")
    func sql() throws {
        let source = "```sql\nSELECT 1;\n```"
        let target = try #require(CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source)).first)
        #expect(target.language == .sql)
        #expect(!target.canRun)
        #expect(!target.isOutput)
    }

    @Test("Retagging reaches Output, and leaves it")
    func retag() throws {
        func result(_ line: String, _ kind: CodeBlockKind) throws -> String {
            let edit = try #require(FenceTag.retag(line: line, to: kind))
            return (line as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        }
        #expect(try result("```python\n", .output) == "```output\n")
        #expect(try result("```\n", .output) == "```output\n")
        #expect(try result("```output\n", .language(.cpp)) == "```cpp\n")
        #expect(try result("```output\n", .plain) == "```\n")
        #expect(FenceTag.retag(line: "```output\n", to: .output) == nil)
        #expect(try result("```ruby\n", .language(.rust)) == "```rust\n")
    }

    // MARK: Colours

    private func luminance(_ hex: UInt32) -> Double {
        let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { byte -> Double in
            let c = Double(byte) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    @Test("The output text is 4.5:1 on its panel in both appearances")
    func textContrast() {
        for tokens in [CodeOutputPanel.light, CodeOutputPanel.dark] {
            #expect(contrast(tokens.text, tokens.fill) >= 4.5)
        }
    }

    @Test("The Output label is legible on its panel in both appearances")
    func labelContrast() {
        // The design's own tokens (`Code` board). The label is 13pt semibold
        // and the dark one is the weaker, so the bar here is 4:1, and the
        // measured ratios are in the PR.
        for tokens in [CodeOutputPanel.light, CodeOutputPanel.dark] {
            let ratio = contrast(tokens.label, tokens.fill)
            #expect(ratio >= 4.0, "\(String(tokens.label, radix: 16)) on \(String(tokens.fill, radix: 16)) is \(ratio):1")
        }
    }

    // MARK: On the page

    @Test("An output block's panel is the console's, in both appearances", arguments: [UIUserInterfaceStyle.light, .dark])
    func panelPixels(style: UIUserInterfaceStyle) async throws {
        let harness = CodeFenceDisplayTests.Harness(Self.note, style: style)
        try await harness.caret(at: 0)

        let tokens = style == .dark ? CodeOutputPanel.dark : CodeOutputPanel.light
        let mean = CodeFenceDisplayTests.meanColor(
            of: harness.textView,
            in: harness.interior(of: harness.rect(of: "after:  3 -> 2 -> 1"))
        )
        // Text and panel mixed, so the mean sits near the panel: closer to it
        // than to the page's own colour.
        let fill = (r: Double((tokens.fill >> 16) & 0xFF), g: Double((tokens.fill >> 8) & 0xFF), b: Double(tokens.fill & 0xFF))
        let page = style == .dark ? (r: 0.0, g: 0.0, b: 0.0) : (r: 255.0, g: 255.0, b: 255.0)
        func distance(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
            abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
        }
        #expect(distance(mean, fill) < distance(mean, page), "mean \(mean) is nearer the page than the console's \(fill)")
        #expect(distance(mean, fill) < 120, "mean \(mean) vs console \(fill)")
    }

    @Test("A code block beside it keeps the ordinary panel")
    func codePanelUnchanged() async throws {
        let harness = CodeFenceDisplayTests.Harness(Self.note, style: .light)
        try await harness.caret(at: 0)
        let mean = CodeFenceDisplayTests.meanColor(of: harness.textView, in: harness.interior(of: harness.rect(of: "int main() {}")))
        // secondarySystemBackground, F2F2F7, with some glyph pixels in it.
        #expect(mean.r > 200 && mean.g > 200 && mean.b > 200, "\(mean)")
    }

    @Test("Output text takes the console's colour, and highlighting leaves it alone")
    func textColour() async throws {
        let harness = CodeFenceDisplayTests.Harness(Self.note, style: .light)
        try await harness.caret(at: 0)
        let offset = harness.offset(of: "before: 1")
        let colour = harness.textView.textStorage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor
        #expect(colour == CodeOutputPanel.textColor)

        // Past the highlighter's delay and its pass: a block it was handed
        // would have been reset to `.label` here.
        try await harness.settle()
        try await harness.settle()
        let after = harness.textView.textStorage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor
        #expect(after == CodeOutputPanel.textColor)
    }

    @Test("Retagging a block to Output turns every line of it into the console, and back")
    func retagTurnsEveryLine() async throws {
        let source = "```python\nprint(1)\nprint(2)\nprint(3)\n```\n"
        let harness = CodeFenceDisplayTests.Harness(source, style: .light)
        try await harness.caret(at: harness.source.length)
        try await harness.settle()

        func outputFlags() -> [Bool] {
            var flags: [Bool] = []
            harness.textView.textLayoutManager?.enumerateTextLayoutFragments(
                from: harness.textView.textLayoutManager?.documentRange.location, options: [.ensuresLayout]
            ) { fragment in
                if let code = fragment as? CodeBlockLayoutFragment { flags.append(code.isOutput) }
                return true
            }
            return flags
        }
        #expect(outputFlags() == [false, false, false, false, false])

        // Python and output are the same length, so nothing about the block's
        // size tells the styler it changed.
        let target = try #require(CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source)).first)
        harness.coordinator.setKind(.output, of: target, in: harness.textView)
        try await harness.settle()
        #expect(outputFlags() == [true, true, true, true, true])
        let colour = harness.textView.textStorage.attribute(.foregroundColor, at: harness.offset(of: "print(2)"), effectiveRange: nil) as? UIColor
        #expect(colour == CodeOutputPanel.textColor)

        let output = try #require(CodeBlockAction.targets(in: harness.textView.text, blocks: DocumentParser.parse(harness.textView.text)).first)
        harness.coordinator.setKind(.language(.python), of: output, in: harness.textView)
        try await harness.settle()
        try await harness.settle()
        #expect(outputFlags() == [false, false, false, false, false])
        let back = harness.textView.textStorage.attribute(.foregroundColor, at: harness.offset(of: "print(2)"), effectiveRange: nil) as? UIColor
        #expect(back != CodeOutputPanel.textColor, "python's text isn't left in the console's colour")
    }

    @Test("The action bar: Copy alone for Output and SQL, both for a language that runs")
    func bars() async throws {
        let harness = CodeFenceDisplayTests.Harness(
            "```rust\nfn main() {}\n```\n```sql\nSELECT 1;\n```\n```output\nok\n```\n", style: .light
        )
        try await harness.caret(at: harness.source.length)
        try await harness.settle()
        let bars = harness.textView.subviews.compactMap { $0 as? CodeBlockActionBar }.sorted { $0.frame.minY < $1.frame.minY }
        #expect(bars.count == 3)
        #expect(bars.map(\.frame.width) == [CodeBlockActionBar.size.width, CodeBlockActionBar.copyOnlySize.width, CodeBlockActionBar.copyOnlySize.width])
    }
}

#endif
