//
//  ProseBlockTests.swift
//  NoteCodeTests
//
//  Text overhaul, phase 6: block quotes, `> `, and horizontal rules, `---`.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Quotes and rules: reading")
struct ProseBlockParsingTests {

    @Test("A quote line has as many levels as >s, its marker is the >s and the spaces after them, and its text follows",
          arguments: [
            ("> a", 1, "> ", "a"), (">a", 1, ">", "a"), (">> a", 2, ">> ", "a"), ("> > a", 2, "> > ", "a"),
            ("   > a", 1, "   > ", "a"), (">", 1, ">", ""), ("> ", 1, "> ", ""), (">  a", 1, "> ", " a"),
            ("> a > b", 1, "> ", "a > b"), ("> **b**", 1, "> ", "**b**"),
          ])
    func quotes(line: String, depth: Int, marker: String, content: String) throws {
        let block = try #require(DocumentParser.parse(line).first)
        #expect(block.quoteDepth == depth)
        #expect(block.markerRange.map { String(line[$0]) } == marker)
        #expect(String(line[block.contentRange]) == content)
        // The inlines still cover the content, to the character.
        #expect(block.inlines.map { String(line[$0.range]) }.joined() == content)
    }

    @Test("What only looks like a quote is prose", arguments: ["    > a", "a > b", "x>y", "->", "=> a", "<a>"])
    func notQuotes(line: String) {
        #expect(DocumentParser.parse(line).first?.quoteDepth == nil, "\(line)")
    }

    @Test("Three hyphens or more, alone on the line, are a rule", arguments: ["---", "-----", "   ---", "--- ", "---\t", "----------"])
    func rules(line: String) throws {
        let block = try #require(DocumentParser.parse(line).first)
        #expect(block.isRule, "\(line)")
        // The dashes are the marker; nothing is left to read.
        #expect(block.markerRange.map { String(line[$0]) } == line)
        #expect(block.contentRange.isEmpty)
    }

    @Test("Anything else is not a rule: two hyphens, spaced ones, other characters, a long indent, a bullet",
          arguments: ["--", "- -", "- - -", "***", "___", "----a", "---x", "    ---", "-- -", "- ---", "a ---", "===", "—"])
    func notRules(line: String) {
        #expect(DocumentParser.parse(line).first?.isRule != true, "\(line)")
    }

    @Test("A rule on a line with a terminator keeps the terminator as its content, as a heading's text is")
    func ruleTerminator() throws {
        let text = "---\nafter"
        let blocks = DocumentParser.parse(text)
        #expect(blocks.count == 2)
        #expect(blocks[0].isRule)
        #expect(String(text[blocks[0].range]) == "---\n")
        #expect(String(text[blocks[0].contentRange]) == "\n")
        #expect(blocks[0].inlines.count == 1)
    }

    /// Whatever the lines are, the blocks cover the text with no gap and no
    /// overlap: the styler, the layout and the carets all rely on it.
    @Test("Blocks of quotes, rules and everything else cover the note exactly")
    func coverage() {
        let pool = ["---", "> q", ">> q", ">", "# h", "- item", "- [ ] box", "plain", "", "```cpp", "```", "1. one", "***", "  ---", "text > more"]
        var random = NestingInlineTests.Seeded(state: 22_10_2026)
        for _ in 0..<2000 {
            let text = (0..<Int.random(in: 1...9, using: &random)).map { _ in pool.randomElement(using: &random)! }.joined(separator: "\n")
            var cursor = text.startIndex
            for block in DocumentParser.parse(text) {
                #expect(block.range.lowerBound == cursor, "gap before a block in \(text.debugDescription)")
                cursor = block.range.upperBound
                if !block.isCode {
                    #expect(block.contentRange.upperBound == block.range.upperBound)
                    #expect(block.inlines.first.map { $0.range.lowerBound == block.contentRange.lowerBound } ?? block.contentRange.isEmpty)
                }
            }
            // A trailing empty line after the last newline spans nothing.
            #expect(text[cursor...].allSatisfy { $0 == "\n" || $0 == "\r\n" }, "uncovered text in \(text.debugDescription)")
        }
    }

    @Test("A quote's text is inline Markdown and no other block: a heading or a list inside is text")
    func nothingInside() throws {
        let heading = try #require(DocumentParser.parse("> # h").first)
        #expect(heading.quoteDepth == 1 && heading.headingLevel == nil)
        let item = try #require(DocumentParser.parse("> - a").first)
        #expect(item.quoteDepth == 1 && item.listMarker == nil)
        let bold = try #require(DocumentParser.parse("> **b** c").first)
        #expect(bold.inlines.contains { $0.attributes.bold })
    }

    @Test("The block signature tells a quote from a paragraph of the same length, and one depth from another")
    func signatures() {
        func signature(_ line: String) -> DocumentStylerSignature? {
            DocumentParser.parse(line).first.map { DocumentStylerSignature(kind: $0.kindDiscriminant, detail: $0.styleDetail) }
        }
        #expect(signature("> a") != signature("xxx"))
        #expect(signature("> a") != signature(">>a"))
        #expect(signature("---") != signature("xxx"))
    }
}

private struct DocumentStylerSignature: Equatable {
    var kind: Int
    var detail: Int
}

@Suite("Quotes and rules: editing")
struct ProseBlockEditingTests {

    private func returned(_ marked: String, rendered: Bool = true) -> String? {
        let text = marked.replacingOccurrences(of: "|", with: "")
        let caret = (marked as NSString).range(of: "|").location
        guard let edit = MarkdownFormatting.returnEdit(in: text as NSString, caret: caret, rendered: rendered, codeRanges: []) else { return nil }
        let result = edit.applied(to: text) as NSString
        return result.substring(to: edit.selection.location) + "|" + result.substring(from: edit.selection.location)
    }

    @Test("Return in a quote starts the next line with the same >s")
    func returnContinues() {
        #expect(returned("> one|") == "> one\n> |")
        #expect(returned(">> deep|") == ">> deep\n>> |")
        #expect(returned("> > deep|") == "> > deep\n> > |")
        // Text after the caret moves down with it.
        #expect(returned("> ab|cd") == "> ab\n> |cd")
    }

    @Test("Return on an empty quote line ends the quote, as it ends a list")
    func returnEnds() {
        #expect(returned("> |") == "|")
        #expect(returned(">|") == "|")
    }

    @Test("Return before the marker, or at the start of the line, is a plain newline")
    func returnBeforeMarker() {
        #expect(returned("|> one") == nil)
    }

    @Test("Quote on a line adds a > and Quote again takes it off; the words and the caret stay")
    func toggleQuote() {
        func toggled(_ marked: String) -> String {
            let text = marked.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
            let ns = marked as NSString
            let open = ns.range(of: "«").location
            let close = ns.range(of: "»").location
            let edit = MarkdownFormatting.toggleQuote(in: text, selection: NSRange(location: open, length: close - open - 1))
            let result = edit.applied(to: text) as NSString
            return result.substring(to: edit.selection.location) + "«" + result.substring(with: edit.selection) + "»"
                + result.substring(from: NSMaxRange(edit.selection))
        }
        #expect(toggled("wo«»rd") == "> wo«»rd")
        #expect(toggled("> wo«»rd") == "wo«»rd")
        #expect(toggled(">> wo«»rd") == "wo«»rd")
        // A selection that began at a line's start still takes in the marker.
        #expect(toggled("«one\ntwo»") == "«> one\n> two»")
        // A heading's or a list's marker gives way to the quote's.
        #expect(toggled("# ti«»tle") == "> ti«»tle")
        #expect(toggled("- it«»em") == "> it«»em")
        // Some quoted, some not: all become quotes, and the quoted ones keep theirs.
        #expect(toggled("«> one\ntwo»") == "«> one\n> two»")
    }

    @Test("A rule goes on its own line below the caret's, with a blank line between if there was text and the caret under it")
    func insertRule() throws {
        func inserted(_ marked: String) -> String? {
            let text = marked.replacingOccurrences(of: "|", with: "")
            let caret = (marked as NSString).range(of: "|").location
            guard let edit = MarkdownFormatting.insertRule(in: text, selection: NSRange(location: caret, length: 0)) else { return nil }
            let result = edit.applied(to: text) as NSString
            return result.substring(to: edit.selection.location) + "|" + result.substring(from: edit.selection.location)
        }
        #expect(inserted("text|") == "text\n\n---\n|")
        #expect(inserted("te|xt\nnext") == "text\n\n---\n|\nnext")
        #expect(inserted("above\n|\nbelow") == "above\n---\n|\nbelow")
        #expect(inserted("above\n|") == "above\n---\n|")
        #expect(inserted("|") == "---\n|")
        // What it wrote is a rule, and nothing else changed.
        let text = try #require(inserted("text|")).replacingOccurrences(of: "|", with: "")
        #expect(DocumentParser.parse(text).map(\.isRule) == [false, false, true])
    }

    @Test("No rule goes into a code block")
    func noRuleInCode() {
        let text = "```cpp\nint x;\n```\n"
        let ranges = [CodeRange(range: NSRange(location: 0, length: 17), isClosed: true)]
        #expect(MarkdownFormatting.insertRule(in: text, selection: NSRange(location: 10, length: 0), codeRanges: ranges) == nil)
    }

    @Test("The caret stops after a quote's marker and after a rule's dashes, wherever it lands in them")
    func caretStops() {
        let text = "> quoted\n---\nplain" as NSString
        // In the marker of the quote.
        #expect(MarkdownFormatting.caretStop(for: 0, direction: 0, in: text, codeRanges: []) == 2)
        #expect(MarkdownFormatting.caretStop(for: 1, direction: 0, in: text, codeRanges: []) == 2)
        #expect(MarkdownFormatting.caretStop(for: 5, direction: 0, in: text, codeRanges: []) == 5)
        // In the dashes of the rule.
        let rule = text.range(of: "---").location
        for offset in rule...(rule + 3) {
            #expect(MarkdownFormatting.caretStop(for: offset, direction: 0, in: text, codeRanges: []) == rule + 3, "offset \(offset)")
        }
    }

    @Test("Backspace at the start of a quote's text takes the marker, and at the end of a rule takes the dashes")
    func backspace() throws {
        let quote = "> quoted" as NSString
        let edit = try #require(MarkdownFormatting.backspace(at: 2, in: quote, codeRanges: []))
        #expect(edit.applied(to: quote as String) == "quoted")

        let text = "above\n---\nbelow" as NSString
        let end = text.range(of: "---").location + 3
        let ruleEdit = try #require(MarkdownFormatting.backspace(at: end, in: text, codeRanges: []))
        #expect(ruleEdit.applied(to: text as String) == "above\n\nbelow")
    }

    @Test("The bar's stretches are one per run of lines that touch, and a gap between lines is left clear")
    func barRuns() {
        #if canImport(UIKit)
        let runs = ProseBlockMetrics.barRuns(of: [0...20, 20...40, 60...80, 80.2...100])
        #expect(runs == [0...40, 60...100])
        #expect(ProseBlockMetrics.barRuns(of: []).isEmpty)
        #endif
    }

    @Test("The text options row and the Style menu know a quote's depth")
    func caretFormatting() {
        let text = ">> a" as NSString
        let state = MarkdownFormatting.formatting(at: NSRange(location: 4, length: 0), in: text, codeRanges: [])
        #expect(state.quoteDepth == 2)
        #expect(MarkdownFormatting.formatting(at: NSRange(location: 1, length: 0), in: "a" as NSString, codeRanges: []).quoteDepth == 0)
    }
}

#if canImport(UIKit)

import UIKit

@Suite("Quotes and rules: on the page")
@MainActor
struct ProseBlockLayoutTests {

    static let note = [
        "A plain line before, long enough to read as a paragraph of ordinary text.",
        "> The first quoted line" + MarkdownLayoutTests.long,
        "> The second quoted line",
        ">> A line nested one deeper",
        "",
        "---",
        "",
        "# Heading",
        "",
        "#### A fourth-level heading",
        "###### A sixth-level heading",
        "",
        "Text with <u>an underlined word</u> and ==🟡a highlighted one== and ==🔴a red one====🔵beside a blue one==.",
        "",
    ].joined(separator: "\n")

    @Test("Every line is where it would be if the markers weren't there, quotes, rules, underline and highlight included",
          arguments: [PageLayout(), PageLayout(mode: .print), PageLayout(orientation: .landscape)])
    func linesEqualMarkerlessLines(layout: PageLayout) {
        let (rendered, deleted) = MarkdownLayoutTests.pair(Self.note, layout: layout)
        let a = CodeFenceDisplayTests.lineFrames(of: rendered.textView)
        let b = CodeFenceDisplayTests.lineFrames(of: deleted.textView)
        #expect(a.count > 12)
        #expect(a.count == b.count)
        for (index, (x, y)) in zip(a, b).enumerated() {
            #expect(
                abs(x.minX - y.minX) < 0.01 && abs(x.minY - y.minY) < 0.01 && abs(x.width - y.width) < 0.5 && abs(x.height - y.height) < 0.01,
                "frame \(index) is \(x), expected \(y)"
            )
        }
    }

    @Test("Markers of every new mark and block are laid out at no width")
    func markersCollapse() {
        let harness = CodeFenceDisplayTests.Harness(Self.note)
        let source = harness.textView.textStorage.string
        let runs = MarkdownLayout.runs(for: DocumentParser.parse(source), in: source)
        let collapsed = runs.map { (source as NSString).substring(with: $0.range) }
        #expect(collapsed.contains("> "))
        #expect(collapsed.contains(">> "))
        #expect(collapsed.contains("---"))
        #expect(collapsed.contains("<u>") && collapsed.contains("</u>"))
        #expect(collapsed.contains("==🟡") && collapsed.contains("==🔵"))
        #expect(collapsed.contains("####") == false, "a heading's hashes are \"#### \"")
        #expect(collapsed.contains("#### ") && collapsed.contains("###### "))
        // Each is replaced unit for unit, so offsets still point at the note.
        for run in runs { #expect(run.replacement.utf16.count == run.range.length) }
    }

    @Test("A quote's text is indented past its bar, wrapped lines hang there, and a plain line is not")
    func indent() throws {
        let harness = CodeFenceDisplayTests.Harness(Self.note)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let plain = harness.rect(of: "A plain")
        let first = harness.rect(of: "The first")
        let nested = harness.rect(of: "A line nested")
        #expect(abs((first.minX - plain.minX) - ProseBlockMetrics.quoteIndent) < 0.5)
        #expect(abs((nested.minX - plain.minX) - 2 * ProseBlockMetrics.quoteIndent) < 0.5)
        // The first character of the quote's second line, which it wraps
        // onto, stands where the first line's text does.
        let secondLine = CGPoint(x: first.minX + 0.5, y: first.maxY + first.height / 2)
        let position = try #require(harness.textView.closestPosition(to: secondLine))
        let offset = harness.textView.offset(from: harness.textView.beginningOfDocument, to: position)
        #expect(offset > harness.offset(of: "The first") + 20, "the point is on the quote's wrapped line")
        let start = try #require(harness.textView.position(from: harness.textView.beginningOfDocument, offset: harness.offset(of: "The first")))
        #expect(
            abs(harness.textView.caretRect(for: position).minX - harness.textView.caretRect(for: start).minX) < 0.5,
            "a wrapped line hangs at the quote's text"
        )
    }

    @Test("The paragraph styles carry the indent: in the storage, and in what is typed next")
    func styles() throws {
        let harness = CodeFenceDisplayTests.Harness("> quoted\n>> deeper\nplain\n")
        let storage = harness.textView.textStorage
        func indent(at offset: Int) -> CGFloat? {
            (storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent
        }
        #expect(indent(at: 3) == ProseBlockMetrics.quoteIndent)
        #expect(indent(at: 12) == 2 * ProseBlockMetrics.quoteIndent)
        #expect((indent(at: 22) ?? 0) == 0)

        harness.textView.selectedRange = NSRange(location: 8, length: 0)
        DocumentStyler.applyTypingAttributes(
            to: harness.textView, source: storage.string, blocks: DocumentParser.parse(storage.string)
        )
        let typing = harness.textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(typing?.headIndent == ProseBlockMetrics.quoteIndent)
    }

    // MARK: Pixels

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    /// Whether a pixel is the page's white, to a little: the bars and rules
    /// are light greys.
    private static func isInk(_ pixels: [UInt8], _ index: Int) -> Bool {
        pixels[index] < 235 || pixels[index + 1] < 235 || pixels[index + 2] < 235
    }

    @Test("A quote has its bar beside it on the page, in the room the indent leaves; a plain line has none there")
    func barIsDrawn() throws {
        let harness = CodeFenceDisplayTests.Harness("Plain line\n\n> A quoted line\n\nPlain again\n", style: .light)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let image = CodeFenceDisplayTests.render(harness.textView)
        let pixels = Self.rgba(image)
        let scale = CGFloat(image.width) / harness.textView.bounds.width

        func inkInBar(of text: String) -> Int {
            let line = harness.rect(of: text)
            // The room between the column's edge and the quote's text.
            let left = line.minX - ProseBlockMetrics.quoteIndent
            var count = 0
            for y in Int((line.minY + 2) * scale)..<Int((line.maxY - 2) * scale) {
                for x in Int((left + 1) * scale)..<Int((left + ProseBlockMetrics.quoteIndent - 2) * scale) {
                    if Self.isInk(pixels, (y * image.width + x) * 4) { count += 1 }
                }
            }
            return count
        }
        let barHeight = Int(harness.rect(of: "A quoted").height * scale)
        #expect(inkInBar(of: "A quoted") > barHeight * Int(ProseBlockMetrics.barWidth * scale) / 2, "no bar beside the quote")

        // The same room beside the plain line below it, which is the same
        // distance from the column's edge, holds nothing but its own letters
        // (it begins at the edge, so look where the quote's text would be).
        let plain = harness.rect(of: "Plain again")
        let beside = Int(plain.height * scale)
        var strayInk = 0
        for y in Int(plain.minY * scale)..<Int(plain.maxY * scale) {
            for x in Int((plain.minX - 14) * scale)..<Int((plain.minX - 2) * scale) where Self.isInk(pixels, (y * image.width + x) * 4) {
                strayInk += 1
            }
        }
        #expect(strayInk == 0 && beside > 0)
    }

    @Test("A rule is drawn across the column, level with its line, in both appearances", arguments: [UIUserInterfaceStyle.light, .dark])
    func ruleIsDrawn(style: UIUserInterfaceStyle) throws {
        let harness = CodeFenceDisplayTests.Harness("Above\n\n---\n\nBelow\n", style: style)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let image = CodeFenceDisplayTests.render(harness.textView)
        let pixels = Self.rgba(image)
        let scale = CGFloat(image.width) / harness.textView.bounds.width

        let container = harness.textView.textContainer
        let column = container.size.width - 2 * container.lineFragmentPadding
        let rule = harness.rect(of: "---")
        let page = (pixels[0], pixels[1], pixels[2])

        var widest = 0
        for y in Int(rule.minY * scale)..<Int(rule.maxY * scale) {
            var count = 0
            for x in 0..<image.width where (pixels[(y * image.width + x) * 4], pixels[(y * image.width + x) * 4 + 1], pixels[(y * image.width + x) * 4 + 2]) != page {
                count += 1
            }
            widest = max(widest, count)
        }
        #expect(CGFloat(widest) > column * scale * 0.95, "the rule is \(widest)px across a column of \(Int(column * scale))")
        #expect(CGFloat(widest) < column * scale * 1.05)
    }

    private func picture(_ text: String) async throws -> (data: [UInt8], width: Int, height: Int) {
        let source = NoteThumbnail.Source(text: text, orientation: .portrait, drawingData: Data(), rendersMarkdown: true)
        let image = try #require(await NoteThumbnail.render(source)).cgImage!
        return (Self.rgba(image), image.width, image.height)
    }

    @Test("The thumbnail and the PDF draw a rule: a line across the page's column")
    func printedRule() async throws {
        let rule = try await picture("---\n")
        var widest = 0
        for y in 0..<rule.height {
            var count = 0
            for x in 0..<rule.width where Self.isInk(rule.data, (y * rule.width + x) * 4) { count += 1 }
            widest = max(widest, count)
        }
        // The column is 672 of the page's 816 units wide.
        #expect(Double(widest) > Double(rule.width) * 0.72, "no rule across the thumbnail: widest row \(widest) of \(rule.width)")
    }

    /// The tallest unbroken stretch of ink in any one column of `x` and
    /// `rows`: a bar is a stripe a line tall, which a glyph is not. Counted
    /// this way because the markers' own glyphs, were they drawn, would be ink
    /// in the room beside the text too.
    private func tallestStripe(_ p: (data: [UInt8], width: Int, height: Int), columns: Range<Int>) -> Int {
        var tallest = 0
        for x in columns {
            var run = 0
            for y in 0..<p.height {
                if Self.isInk(p.data, (y * p.width + x) * 4) { run += 1; tallest = max(tallest, run) } else { run = 0 }
            }
        }
        return tallest
    }

    @Test("The thumbnail and the PDF draw a quote's bars, in the room beside its text, a line tall each")
    func printedBars() async throws {
        // Three levels deep, so the room beside the text holds only bars.
        let plain = try await picture("a\n")
        let quoted = try await picture(">>> a\n")
        let leftmost = (0..<plain.height).flatMap { y in (0..<plain.width).filter { Self.isInk(plain.data, (y * plain.width + $0) * 4) } }.min() ?? 0
        let unit = Double(plain.width) / 816
        let room = (leftmost + Int(12 * unit))..<(leftmost + Int(44 * unit))
        // A line of text is 22 units tall: a bar covers most of it, and the
        // thumbnail's pixels are .55 of a unit.
        #expect(tallestStripe(plain, columns: room) == 0)
        #expect(tallestStripe(quoted, columns: room) >= 9, "no bar in the thumbnail")

        // The markers are not drawn in it: the text is where three levels of
        // indent put it, and nothing else is left of it.
        let ink = (0..<quoted.height).flatMap { y in (0..<quoted.width).filter { Self.isInk(quoted.data, (y * quoted.width + $0) * 4) } }
        #expect((ink.max() ?? 0) < leftmost + Int(80 * unit))
    }
}

#endif
