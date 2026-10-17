//
//  CodeBlockRoomTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

/// The room around and inside a code block (step 10): the panel reaching into
/// the margins, the gaps above and below it and the header, all of them line
/// height and none of them paragraph spacing.
@Suite("Room around and inside a code block")
@MainActor
struct CodeBlockRoomTests {

    typealias Harness = CodeFenceDisplayTests.Harness

    // MARK: Pure

    @Test("The header is the opening fence's line less the gap above it")
    func header() {
        let line = CGRect(x: 77, y: 300, width: 600, height: 52)
        let header = CodeBlockRoom.header(ofFenceLine: line)

        #expect(header.minY == 300 + CodeBlockRoom.gapAbove)
        #expect(header.maxY == line.maxY)
        #expect(header.minX == line.minX && header.width == line.width)
    }

    @Test("The panel reaches the same distance past the text column on both sides")
    func span() {
        let span = CodeBlockRoom.panelSpan(textLeft: 5, textRight: 667)

        #expect(span.left == 5 - CodeBlockRoom.outset)
        #expect(span.right == 667 + CodeBlockRoom.outset)
    }

    @Test("Code is smaller than the body, in proportion at every size, on the prose's line height")
    func codeSize() {
        #expect(NoteTypography.standard.code.pointSize == 15)
        for size in NoteTypography.sizes {
            let typography = NoteTypography(bodySize: size)
            #expect(typography.code.pointSize < typography.prose.pointSize)
            #expect(typography.code.pointSize >= typography.prose.pointSize * 0.85)
        }
    }

    // MARK: Laid out

    /// Each laid-out line with the text it holds, in the text view's
    /// coordinates.
    static func lines(of textView: UITextView) -> [(text: String, frame: CGRect)] {
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager else { return [] }
        let string = textView.textStorage.string as NSString
        let inset = textView.textContainerInset
        var lines: [(String, CGRect)] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let origin = fragment.layoutFragmentFrame.origin
            for line in fragment.textLineFragments {
                let location = start + line.characterRange.location
                let length = min(line.characterRange.length, max(0, string.length - location))
                let text = string.substring(with: NSRange(location: location, length: length)).trimmingCharacters(in: .newlines)
                lines.append((text, line.typographicBounds.offsetBy(dx: origin.x + inset.left, dy: origin.y + inset.top)))
            }
            return true
        }
        return lines
    }

    /// Measured, not computed: TextKit's height for a fixed-height line with
    /// a raised baseline is what `CodeBlockRoom` assumes it is. If it weren't,
    /// the gaps and the header would come out a few points off.
    @Test("The fences hold the gaps, the header and the footer; code lines are a prose line tall")
    func lineHeights() throws {
        let harness = Harness()
        let lines = Self.lines(of: harness.textView)
        let typography = NoteTypography.standard

        let opening = try #require(lines.first { $0.text == "```cpp" })
        let closing = try #require(lines.first { $0.text == "```" })
        let code = try #require(lines.first { $0.text.hasPrefix("int value") })
        let prose = try #require(lines.first { $0.text == "Prose before" })

        #expect(abs(opening.frame.height - (CodeBlockRoom.gapAbove + CodeBlockRoom.headerHeight)) < 0.01)
        let footer = CodeBlockRoom.footerHeight(font: typography.code)
        #expect(abs(closing.frame.height - (footer + CodeBlockRoom.gapBelow)) < 0.01)
        #expect(abs(code.frame.height - typography.codeLineHeight) < 0.01)
        #expect(abs(code.frame.height - prose.frame.height) < 0.01)
    }

    @Test("The panel reaches into the margins and the code keeps the prose column", arguments: [UIUserInterfaceStyle.light, .dark])
    func reachesIntoMargins(style: UIUserInterfaceStyle) throws {
        let harness = Harness(style: style)
        let textView = harness.textView
        let code = harness.rect(of: "int value")
        let prose = harness.rect(of: "Prose before")

        #expect(abs(code.minX - prose.minX) < 0.5)

        let textLeft = textView.textContainerInset.left + textView.textContainer.lineFragmentPadding
        let inside = CGRect(x: textLeft - CodeBlockRoom.outset + 3, y: code.midY - 2, width: 4, height: 4)
        let outside = CGRect(x: textLeft - CodeBlockRoom.outset - 8, y: code.midY - 2, width: 4, height: 4)

        let panel = CodeFenceDisplayTests.meanColor(of: textView, in: inside)
        let page = CodeFenceDisplayTests.meanColor(of: textView, in: outside)
        let expected = UIColor.secondarySystemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        expected.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(abs(panel.r - red * 255) < 3 && abs(panel.g - green * 255) < 3 && abs(panel.b - blue * 255) < 3,
                "\(panel) beside the code isn't the panel")
        #expect(abs(page.r - panel.r) + abs(page.g - panel.g) + abs(page.b - panel.b) > 6,
                "\(page) past the panel's edge is the panel colour too")
    }

    @Test("The language and the buttons are centred in the header, inside the panel")
    func headerHoldsTheControls() throws {
        let harness = Harness()
        let opening = try #require(Self.lines(of: harness.textView).first { $0.text == "```cpp" })
        let header = CodeBlockRoom.header(ofFenceLine: opening.frame)

        let bar = try #require(harness.textView.subviews.compactMap { $0 as? CodeBlockActionBar }.first { !$0.isHidden })
        let language = try #require(harness.languageButton)

        #expect(abs(bar.frame.midY - header.midY) < 0.01)
        #expect(abs(language.frame.midY - header.midY) < 0.01)
        #expect(bar.frame.minY > header.minY)
        #expect(bar.frame.maxY < header.maxY)
    }

    // MARK: Glyphs while editing

    /// The rows of `rect` holding anything but the background, in the text
    /// view's coordinates: where glyphs are drawn.
    static func inkRows(of view: UIView, in rect: CGRect) -> ClosedRange<CGFloat>? {
        let scale: CGFloat = 2
        let local = rect.offsetBy(dx: -view.bounds.minX, dy: -view.bounds.minY)
        guard let image = CodeFenceDisplayTests.render(view, scale: scale).cropping(to: CGRect(
            x: local.minX * scale, y: local.minY * scale, width: local.width * scale, height: local.height * scale
        )) else { return nil }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let base = (pixels[0], pixels[1], pixels[2])
        var rows: [Int] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                let pixel = (pixels[i], pixels[i + 1], pixels[i + 2])
                if abs(Int(pixel.0) - Int(base.0)) + abs(Int(pixel.1) - Int(base.1)) + abs(Int(pixel.2) - Int(base.2)) > 30 {
                    rows.append(y)
                    break
                }
            }
        }
        guard let first = rows.first, let last = rows.last else { return nil }
        return (rect.minY + CGFloat(first) / scale)...(rect.minY + CGFloat(last + 1) / scale)
    }

    @Test("Shown while editing, the opening fence sits in the middle of the header and the closing one in the footer")
    func fenceGlyphsInPlace() async throws {
        let harness = Harness()
        try await harness.caret(at: harness.offset(of: "int value"))
        let lines = Self.lines(of: harness.textView)
        let opening = try #require(lines.first { $0.text == "```cpp" })
        let closing = try #require(lines.first { $0.text == "```" })
        let lastCode = try #require(lines.first { $0.text.hasPrefix("int other") })

        // Only the start of each line, clear of the run and copy buttons.
        let header = CodeBlockRoom.header(ofFenceLine: opening.frame)
        let openingInk = try #require(Self.inkRows(of: harness.textView, in: CGRect(
            x: header.minX, y: header.minY + 1, width: 60, height: header.height - 2
        )))
        #expect(abs((openingInk.lowerBound + openingInk.upperBound) / 2 - header.midY) < 3,
                "fence ink \(openingInk) in a header \(header.minY)...\(header.maxY)")

        let footer = CGRect(x: closing.frame.minX, y: closing.frame.minY, width: 40,
                            height: closing.frame.height - CodeBlockRoom.gapBelow)
        let closingInk = try #require(Self.inkRows(of: harness.textView, in: footer.insetBy(dx: 0, dy: 0.5)))
        #expect(closingInk.lowerBound > lastCode.frame.maxY)
        #expect(closingInk.upperBound < footer.maxY)
        #expect(abs((closingInk.lowerBound + closingInk.upperBound) / 2 - footer.midY) < 3,
                "backticks \(closingInk) in a footer \(footer.minY)...\(footer.maxY)")
    }

    // MARK: Wrapped lines

    @Test("A line's indentation is its leading spaces and tabs, tabs to TextKit's stops")
    func leadingWidth() {
        let advance: CGFloat = 9
        #expect(CodeBlockRoom.leadingWidth(of: "    x = 1", advance: advance) == 36)
        #expect(CodeBlockRoom.leadingWidth(of: "\tx", advance: advance) == 28)
        #expect(CodeBlockRoom.leadingWidth(of: "  \tx", advance: advance) == 28)
        #expect(CodeBlockRoom.leadingWidth(of: "\t\tx", advance: advance) == 56)
        #expect(CodeBlockRoom.leadingWidth(of: "x  y", advance: advance) == 0)
        #expect(CodeBlockRoom.leadingWidth(of: "", advance: advance) == 0)
    }

    @Test("A continuation starts two columns past its line's indentation, never past the cap")
    func continuationIndent() {
        let advance: CGFloat = 9
        #expect(CodeBlockRoom.continuationIndent(leading: 0, advance: advance) == 18)
        #expect(CodeBlockRoom.continuationIndent(leading: 36, advance: advance) == 54)
        #expect(CodeBlockRoom.continuationIndent(leading: 1_000, advance: advance)
                == CodeBlockRoom.maximumContinuationColumns * advance)
    }

    static let wrapNote = "Prose before\n```java\n"
        + "    public static void main(String[] args) { System.out.println(\"gjpqy\"); } // and a comment to wrap it\n"
        + "int x;\n```\nAfter\n"

    /// The lines of the block's long line, after the first: its continuations.
    static func continuations(in harness: Harness) throws -> [(text: String, frame: CGRect)] {
        let lines = Self.lines(of: harness.textView)
        let first = try #require(lines.firstIndex { $0.text.contains("public static") })
        let next = try #require(lines.firstIndex { $0.text == "int x;" })
        return Array(lines[(first + 1)..<next])
    }

    @Test("A wrapped line of code continues past its own indentation")
    func hangingIndent() throws {
        let harness = Harness(Self.wrapNote)
        let continuations = try Self.continuations(in: harness)
        try #require(!continuations.isEmpty, "the long line should wrap")

        let advance = CodeBlockRoom.advance(of: NoteTypography.standard.code)
        let lineStart = harness.rect(of: "public static").minX - 4 * advance
        // Spelled out, not asked of `continuationIndent`, or a broken rule
        // would be expected too.
        let expected = (4 + CodeBlockRoom.continuationColumns) * advance
        for continuation in continuations {
            let start = harness.rect(of: String(continuation.text.prefix(8))).minX
            #expect(abs(start - lineStart - expected) < 0.5, "\(continuation.text) starts at \(start - lineStart)")
        }
        // An unwrapped line is where it always was.
        #expect(abs(harness.rect(of: "int x;").minX - lineStart) < 0.5)
    }

    @Test("A wrap mark is drawn in front of each continuation, and nowhere in the line's own indentation",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func wrapMark(style: UIUserInterfaceStyle) throws {
        let harness = Harness(Self.wrapNote, style: style)
        let continuation = try #require(try Self.continuations(in: harness).first)
        let advance = CodeBlockRoom.advance(of: NoteTypography.standard.code)
        let lineStart = harness.rect(of: "public static").minX - 4 * advance
        let start = harness.rect(of: String(continuation.text.prefix(8))).minX

        let row = continuation.frame.insetBy(dx: 0, dy: 3)
        let hanging = CGRect(x: lineStart + 4 * advance, y: row.minY, width: start - 1 - (lineStart + 4 * advance), height: row.height)
        let ownIndent = CGRect(x: lineStart + 1, y: row.minY, width: 4 * advance - 2, height: row.height)

        #expect(CodeFenceDisplayTests.inkPixels(of: harness.textView, in: hanging) > 10)
        #expect(CodeFenceDisplayTests.inkPixels(of: harness.textView, in: ownIndent) == 0)
    }

    /// A paragraph style is restyled only when its block's signature changes.
    /// A code block's carries a hash of its code, so an edit that keeps the
    /// length but changes a line's indentation still restyles it.
    @Test("Changing a line's indentation without changing its length moves its continuations")
    func indentFollowsEdits() async throws {
        let harness = Harness(Self.wrapNote)
        let advance = CodeBlockRoom.advance(of: NoteTypography.standard.code)
        let lineStart = harness.rect(of: "public static").minX - 4 * advance

        // The second and third of the line's four leading spaces become
        // "//", so it is indented one column, not four. Not the first: typed
        // characters take the typing attributes, whose paragraph style is an
        // unindented line's, and at a paragraph's start that style becomes
        // the paragraph's, which put an unindented line's continuation right
        // with no restyle at all. Selected first, as typing over them would
        // be: an edit of code that isn't the selection is a keyboard
        // correction, and turned away.
        try await harness.select(NSRange(location: harness.offset(of: "    public") + 1, length: 2))
        let textView = harness.textView
        textView.replace(try #require(textView.selectedTextRange), withText: "//")
        try await harness.settle()
        harness.layOut()
        #expect(harness.source.range(of: " // public static").location != NSNotFound)

        let continuation = try #require(try Self.continuations(in: harness).first)
        let moved = harness.rect(of: String(continuation.text.prefix(8))).minX
        let expected = (1 + CodeBlockRoom.continuationColumns) * advance
        #expect(abs(moved - lineStart - expected) < 0.5, "continuation at \(moved - lineStart)")
    }

    // MARK: Pagination

    /// `headings` short headings, `prose` lines, then the block. A heading's
    /// line isn't a prose line tall, so each one moves the block a few points
    /// against the page break; prose alone moves it a whole line at a time,
    /// and a sweep of prose alone tried one place within a line and missed
    /// the failure below (mutation, 16 Oct).
    static func sweepNote(headings: Int, prose: Int) -> String {
        let titles = (0..<headings).map { "#### Step \($0)" }
        let lines = (0..<prose).map { "Line \($0): the loop invariant holds gjpqy." }
        let code = (0..<6).map { "    int v\($0) = g.jump(\($0)); // gjpqy" }.joined(separator: "\n")
        return (titles + lines).joined(separator: "\n") + "\n```cpp\n" + code + "\n```\n"
            + (0..<20).map { "After \($0)." }.joined(separator: "\n")
    }

    /// The reason the room is line height: paragraph spacing above the
    /// opening fence put a block 13.3pt down its page in seamless and at its
    /// top in compressed and print (probe, 16 Oct). The block is moved across
    /// the first page break a few points at a time, so its fence lines land
    /// at every place around it.
    @Test("A block at every place around a page break paginates the same in every mode")
    func paginatesAlike() {
        let body = PageLayout().bodyHeight
        let line = NoteTypography.standard.codeLineHeight
        var mismatches: [String] = []
        for headings in 0...10 {
            // Prose that puts the opening fence near the end of the first
            // page, whatever the headings took.
            let near = Int((body - CGFloat(headings) * 26) / line)
            for prose in (near - 3)...(near + 1) {
                let harness = Harness(Self.sweepNote(headings: headings, prose: prose))
                var placements: [[String]] = []
                for mode in PageViewMode.allCases {
                    let layout = PageLayout(mode: mode)
                    harness.page.pageLayout = layout
                    harness.layOut()
                    placements.append(Self.lines(of: harness.textView).map { line in
                        let y = line.frame.minY
                        let index = layout.pageIndex(atY: y)
                        return "\(line.text.prefix(12)) p\(index) \(String(format: "%.1f", y - layout.bodyTop(ofPage: index)))"
                    })
                }
                if placements[0] != placements[1] || placements[0] != placements[2] {
                    mismatches.append("\(headings) headings, \(prose) lines")
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }
}

#endif
