//
//  FormulaLayoutTests.swift
//  NoteCodeTests
//
//  LaTeX step 3 (docs/design/latex.md › Build steps): an inline formula laid
//  out as one attachment. Ground truth is the same styled note with the whole
//  `$…$` physically replaced by that attachment, so TextKit measures what the
//  swap should be equal to.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Formula layout")
@MainActor
struct FormulaLayoutTests {

    nonisolated static let long = " and some more words so that this line is long enough to wrap onto a second line on the page, where a formula that took the wrong room would move the break."

    nonisolated static let note = [
        "# Sums $\\sum_{i=1}^{n} i$ in a heading",
        "The ratio $\\frac{a+b}{c}$ sits in a line" + long,
        "Small ones $x$ and $y_1$ leave the line alone, and $$\\int_0^1 x\\,dx$$ is display style in a line.",
        "An unfinished $\\frac{1}{ one stays as typed, and so does cost $5 and $10.",
        "A **bold $x^2$** word and `$code$` stay.",
        "Plain closing line.",
        "",
    ].joined(separator: "\n")

    /// The note with every drawn formula replaced by its attachment alone.
    static func replacingFormulas(from harness: CodeFenceDisplayTests.Harness) -> NSAttributedString {
        let storage = harness.textView.textStorage
        let source = storage.string.nativeUTF8
        let runs = MarkdownLayout.runs(for: DocumentParser.parse(source), in: source)
        let text = NSMutableAttributedString(attributedString: storage)
        for run in runs.reversed() {
            switch run.kind {
            case .joiners:
                text.deleteCharacters(in: run.range)
            case .bullet:
                text.replaceCharacters(in: run.range, with: String(MarkdownLayout.bullet))
            case .box:
                text.replaceCharacters(in: run.range, with: String(MarkdownLayout.box))
            case .displayFormula(let tex):
                let attributes = storage.attributes(at: run.range.location, effectiveRange: nil)
                let size = (attributes[.font] as? UIFont)?.pointSize ?? 17
                let replacement = NSMutableAttributedString(string: String(MarkdownLayout.attachmentCharacter), attributes: attributes)
                if let attachment = FormulaAttachment.make(tex: tex, pointSize: size, display: true, fitting: true) {
                    replacement.addAttribute(.attachment, value: attachment, range: NSRange(location: 0, length: 1))
                    let font = attributes[.font] as? UIFont ?? .preferredFont(forTextStyle: .body)
                    replacement.addAttribute(.baselineOffset, value: DisplayFormula.baselineLift(tex: tex, font: font), range: NSRange(location: 0, length: 1))
                }
                text.replaceCharacters(in: run.range, with: replacement)
            case .formula(let tex, let display, let opening):
                let attributes = storage.attributes(at: run.range.location + opening, effectiveRange: nil)
                let size = (attributes[.font] as? UIFont)?.pointSize ?? 17
                let replacement = NSMutableAttributedString(string: String(MarkdownLayout.attachmentCharacter), attributes: attributes)
                if let attachment = FormulaAttachment.make(tex: tex, pointSize: size, display: display) {
                    replacement.addAttribute(.attachment, value: attachment, range: NSRange(location: 0, length: 1))
                }
                text.replaceCharacters(in: run.range, with: replacement)
            }
        }
        return text
    }

    static func pair(_ text: String = note, layout: PageLayout = PageLayout()) -> (rendered: CodeFenceDisplayTests.Harness, truth: CodeFenceDisplayTests.Harness) {
        let rendered = CodeFenceDisplayTests.Harness(text, layout: layout)
        rendered.coordinator.setRendersMarkdown(true, in: rendered.textView)
        rendered.layOut()
        let truth = CodeFenceDisplayTests.Harness(text, layout: layout)
        truth.textView.textStorage.setAttributedString(replacingFormulas(from: rendered))
        truth.layOut()
        return (rendered, truth)
    }

    static func assertSame(_ a: [CGRect], _ b: [CGRect], _ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.count == b.count, "\(message): \(a.count) frames against \(b.count)", sourceLocation: sourceLocation)
        for (index, (x, y)) in zip(a, b).enumerated() {
            #expect(
                abs(x.minX - y.minX) < 0.01 && abs(x.minY - y.minY) < 0.01
                    && abs(x.width - y.width) < 0.5 && abs(x.height - y.height) < 0.01,
                "\(message): frame \(index) is \(x), expected \(y)",
                sourceLocation: sourceLocation
            )
        }
    }

    // MARK: Which formulas are swapped

    @Test("Only formulas that can be drawn become runs; the rest keep their dollars")
    func runsForDrawableOnly() {
        let source = "Draws $x^2$ here, not $\\frac{1}{$ or $\\cancel{x}$.\n"
        let runs = MarkdownLayout.runs(for: DocumentParser.parse(source), in: source)
        let formulas = runs.filter { if case .formula = $0.kind { true } else { false } }
        #expect(formulas.count == 1)
        #expect(formulas.first.map { (source as NSString).substring(with: $0.range) } == "$x^2$")
        // The undrawable ones' dollars are not collapsed.
        #expect(runs.filter { $0.kind == .joiners }.isEmpty)
    }

    @Test("A formula run is as long as its source, so every offset still maps")
    func sameLength() {
        let source = "A $\\dfrac{a}{b}$ and $$x$$ here\n"
        let runs = MarkdownLayout.runs(for: DocumentParser.parse(source), in: source)
        #expect(runs.count == 2)
        for run in runs { #expect(run.replacement.utf16.count == run.range.length) }
        if case .formula(let tex, let display, _) = runs[0].kind {
            #expect(tex == "\\frac{a}{b}")   // through TeXAliases
            #expect(!display)
        } else { Issue.record("not a formula") }
        if case .formula(_, let display, _) = runs[1].kind { #expect(display) } else { Issue.record("not a formula") }
    }

    @Test("The laid-out paragraph holds one attachment per formula, in the TeX's own colour and size")
    func attachment() throws {
        let harness = CodeFenceDisplayTests.Harness("Red <span style=\"color:#FF0000\">$x$</span> end\n")
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        let storage = harness.textView.textStorage
        let source = storage.string.nativeUTF8
        let runs = MarkdownLayout.runs(for: DocumentParser.parse(source), in: source)
        let laid = MarkdownLayout.laidOut(NSRange(location: 0, length: storage.length), of: storage, runs: runs[...])
        #expect(laid.length == storage.length)
        var attachments = 0
        laid.enumerateAttribute(.attachment, in: NSRange(location: 0, length: laid.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        #expect(attachments == 1)
        let at = (laid.string as NSString).range(of: String(MarkdownLayout.attachmentCharacter)).location
        let colour = try #require(laid.attribute(.foregroundColor, at: at, effectiveRange: nil) as? UIColor)
        #expect(colour != DocumentStyler.markerColor)
    }

    @Test("An undrawable formula's source is painted secondaryLabel, dollars included")
    func dimmed() {
        let source = "Bad $\\frac{1}{$ and good $x$\n"
        let harness = CodeFenceDisplayTests.Harness(source)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        let storage = harness.textView.textStorage
        let bad = (source as NSString).range(of: "$\\frac{1}{$")
        for offset in bad.location..<NSMaxRange(bad) {
            #expect(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor == .secondaryLabel,
                    "offset \(offset)")
        }
        let good = (source as NSString).range(of: "x$\n").location
        #expect(storage.attribute(.foregroundColor, at: good, effectiveRange: nil) as? UIColor != .secondaryLabel)
    }

    // MARK: Layout

    @Test("A fraction grows its line; a small formula leaves it alone")
    func lineHeights() {
        let fraction = FormulaAttachment.metrics(tex: "\\frac{a+b}{c}", pointSize: 17, display: false)
        let small = FormulaAttachment.metrics(tex: "x", pointSize: 17, display: false)
        #expect(fraction != nil && small != nil)
        let plain = CodeFenceDisplayTests.Harness("Plain\n")
        let withFraction = CodeFenceDisplayTests.Harness("A $\\frac{a+b}{c}$ b\n")
        withFraction.coordinator.setRendersMarkdown(true, in: withFraction.textView)
        withFraction.layOut()
        let withSmall = CodeFenceDisplayTests.Harness("A $x$ b\n")
        withSmall.coordinator.setRendersMarkdown(true, in: withSmall.textView)
        withSmall.layOut()
        let h = { (harness: CodeFenceDisplayTests.Harness) in CodeBlockRoomTests.lines(of: harness.textView).first!.frame.height }
        // The line grows to the formula's own height (ascent + descent), and no further.
        let formulaHeight = (fraction?.ascent ?? 0) + (fraction?.descent ?? 0)
        #expect(h(withFraction) > h(plain))
        #expect(abs(h(withFraction) - formulaHeight) < 1.0)
        #expect(abs(h(withSmall) - h(plain)) < 1.5)
    }

    @Test("The formula sits on the text's baseline and its width is the line's width")
    func frames() {
        for mode in PageViewMode.allCases {
            for orientation in [PageOrientation.portrait, .landscape] {
                let layout = PageLayout(orientation: orientation, mode: mode)
                let (rendered, truth) = Self.pair(layout: layout)
                Self.assertSame(
                    CodeFenceDisplayTests.lineFrames(of: rendered.textView),
                    CodeFenceDisplayTests.lineFrames(of: truth.textView),
                    "\(mode) \(orientation)"
                )
            }
        }
    }

    /// Prose that puts a formula line near the first page break, then the
    /// formula; the same lines land on the same pages in every mode.
    @Test("A formula at every place around a page break paginates the same in every mode")
    func paginatesAlike() {
        let body = PageLayout().bodyHeight
        let line = NoteTypography.standard.prose.lineHeight
        let near = Int(body / line)
        var mismatches: [String] = []
        for prose in (near - 6)...(near + 1) {
            let text = (0..<prose).map { _ in "Line of prose" }.joined(separator: "\n")
                + "\nTall $\\frac{\\sum_{i} i}{\\sqrt{n}}$ formula line\nTail $x$ line\nEnd\n"
            let harness = CodeFenceDisplayTests.Harness(text)
            harness.coordinator.setRendersMarkdown(true, in: harness.textView)
            var placements: [[String]] = []
            for mode in PageViewMode.allCases {
                let layout = PageLayout(mode: mode)
                harness.page.pageLayout = layout
                harness.layOut()
                placements.append(CodeBlockRoomTests.lines(of: harness.textView).map { line in
                    let y = line.frame.minY
                    let index = layout.pageIndex(atY: y)
                    return "\(line.text.prefix(12)) p\(index) \(String(format: "%.1f", y - layout.bodyTop(ofPage: index)))"
                })
            }
            if placements[0] != placements[1] || placements[0] != placements[2] {
                mismatches.append("\(prose) lines")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }
}

#endif
