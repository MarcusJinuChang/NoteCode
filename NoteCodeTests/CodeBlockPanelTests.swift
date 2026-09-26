//
//  CodeBlockPanelTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Code block panel geometry")
@MainActor
struct CodeBlockPanelTests {

    /// The editor's real line height. `UIFont.monospacedSystemFont(ofSize: 17)`
    /// measures 20.021484375pt, and that fraction is the whole problem: stack a
    /// few of them and the boundaries stop landing on device pixels.
    private static let lineHeight: CGFloat = 20.021484375

    /// Content scales the page actually draws at: PageView's 0.75x to 1.25x,
    /// on 2x and 3x screens.
    private static let scales: [CGFloat] = [1.5, 2.0, 2.49, 3.0, 3.75]

    private static func frames(lines: Int, origin: CGFloat) -> [CGRect] {
        (0..<lines).map { index in
            CGRect(x: 8, y: origin + CGFloat(index) * lineHeight, width: 500, height: lineHeight)
        }
    }

    private static func position(_ index: Int, of lines: Int) -> CodeBlockPosition {
        if lines == 1 { return .only }
        if index == 0 { return .first }
        if index == lines - 1 { return .last }
        return .middle
    }

    /// Panels for a code block of `lines` paragraphs stacked from `origin`.
    private static func panels(lines: Int, origin: CGFloat, scale: CGFloat) -> [CGRect] {
        frames(lines: lines, origin: origin).enumerated().map { index, frame in
            CodeBlockLayoutFragment.panelRect(
                frame: frame,
                position: position(index, of: lines),
                scale: scale
            )
        }
    }

    // MARK: The seam

    @Test("Fragment boundaries fall mid-pixel to begin with", arguments: [2.0, 3.0] as [CGFloat])
    func boundariesAreNotPixelAligned(scale: CGFloat) {
        let boundaries = (1..<6).map { CGFloat($0) * Self.lineHeight }
        #expect(boundaries.contains { ($0 * scale) != ($0 * scale).rounded() })
    }

    @Test(
        "The panel behind overlaps the one in front by two whole pixels",
        arguments: scales, [0.0, 12.0, 0.5, 7.3] as [CGFloat]
    )
    func overlapCoversTheBoundary(scale: CGFloat, origin: CGFloat) {
        // Inside PageView the page is transformed, so neither fragment's pixel
        // grid lines up with the screen's, and edges are filtered. An overlap
        // of whole pixels is the only kind that survives any offset between
        // the two. Rounding to a pixel boundary, the previous approach, could
        // leave none.
        let rects = Self.panels(lines: 6, origin: origin, scale: scale)

        for (upper, lower) in zip(rects, rects.dropFirst()) {
            let overlapPixels = (upper.maxY - lower.minY) * scale
            #expect(overlapPixels >= CodeBlockLayoutFragment.overhangPixels - 0.0001,
                    "overlap of \(overlapPixels)px at scale \(scale), origin \(origin)")
        }
    }

    // MARK: The regression guard

    @Test(
        "A panel never reaches below its own fragment",
        arguments: scales, [0.0, 0.5, 7.3] as [CGFloat]
    )
    func neverPaintsDownward(scale: CGFloat, origin: CGFloat) {
        // This is the one that matters. Each line's view sits in front of the
        // line below it, so a panel reaching down paints over the next line's
        // text. Reaching up lands behind the line above, under its descenders.
        let frames = Self.frames(lines: 6, origin: origin)
        let rects = Self.panels(lines: 6, origin: origin, scale: scale)

        for (frame, rect) in zip(frames, rects) {
            #expect(rect.maxY <= frame.maxY, "panel runs \(rect.maxY - frame.maxY)pt below its fragment")
        }
    }

    @Test("A panel reaches up no further than its rendering surface allows", arguments: [0.5, 1.0] + scales)
    func overhangFitsTheSurface(scale: CGFloat) {
        let frames = Self.frames(lines: 6, origin: 7.3)
        let rects = Self.panels(lines: 6, origin: 7.3, scale: scale)

        for (frame, rect) in zip(frames, rects) {
            #expect(frame.minY - rect.minY <= CodeBlockLayoutFragment.maximumOverhang + .ulpOfOne)
        }
    }

    @Test("The rendering surface leaves room above for the overhang")
    func surfaceHoldsTheOverhang() {
        let paragraph = NSTextParagraph(attributedString: NSAttributedString(string: "int x;\n"))
        let fragment = CodeBlockLayoutFragment(textElement: paragraph, range: paragraph.elementRange)

        #expect(fragment.renderingSurfaceBounds.minY <= -CodeBlockLayoutFragment.maximumOverhang)
    }

    /// The premise the overhang direction rests on. If UIKit ever stacks
    /// fragment views the other way, upward overhang paints over descenders
    /// and this has to be rethought — so it is checked, not assumed.
    @Test("TextKit stacks each line's view in front of the line below it")
    func upperLinesInFront() {
        final class Box { var value = "" }
        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 1400))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        textView.text = "```cpp\n" + (0..<30).map { "int value\($0) = query(gap);" }.joined(separator: "\n") + "\n```"
        coordinator.restyle(textView)

        let page = PageView(textView: textView)
        page.frame = CGRect(x: 0, y: 0, width: 872, height: 1200)
        window.addSubview(page)
        window.makeKeyAndVisible()
        page.layoutIfNeeded()
        textView.layoutIfNeeded()

        var views: [UIView] = []
        func collect(_ view: UIView) {
            if String(describing: type(of: view)).contains("TextLayoutFragmentView") {
                views.append(view)
            }
            view.subviews.forEach(collect)
        }
        collect(textView)

        // Subviews run back to front, so front-most last: y should fall.
        let tops = views.map { $0.convert($0.bounds, to: textView).minY }
        #expect(views.count > 10)
        #expect(tops == tops.sorted(by: >))
    }

    // MARK: Page breaks

    private typealias Run = CodeBlockLayoutFragment.PanelRun

    @Test("With no page break, the panel covers the whole fragment", arguments: [CodeBlockPosition.only, .first, .middle, .last])
    func noBreakOneRun(position: CodeBlockPosition) {
        let frame = CGRect(x: 0, y: 100, width: 500, height: Self.lineHeight * 2)
        let lines = [100...(100 + Self.lineHeight), (100 + Self.lineHeight)...(100 + Self.lineHeight * 2)]

        let runs = CodeBlockLayoutFragment.panelRuns(frame: frame, lines: lines, breaks: [], position: position)

        #expect(runs == [Run(top: frame.minY, bottom: frame.maxY, position: position)])
    }

    @Test("A line pushed onto the next page starts its panel there, not above the break")
    func pushedLineStartsBelowBreak() {
        // The fragment begins at 890, the page ends at 912, a 168pt break
        // follows, and TextKit has placed the line below it.
        let frame = CGRect(x: 0, y: 890, width: 500, height: 1080 + Self.lineHeight - 890)
        let line = CGFloat(1080)...(1080 + Self.lineHeight)
        let pageBreak = CGFloat(912)...1080

        let runs = CodeBlockLayoutFragment.panelRuns(frame: frame, lines: [line], breaks: [pageBreak], position: .middle)

        #expect(runs == [Run(top: 1080, bottom: frame.maxY, position: .middle)])
    }

    @Test("A block that starts on a new page keeps its rounded top")
    func pushedFirstLineKeepsTop() {
        let frame = CGRect(x: 0, y: 890, width: 500, height: 1080 + Self.lineHeight - 890)
        let runs = CodeBlockLayoutFragment.panelRuns(
            frame: frame,
            lines: [CGFloat(1080)...(1080 + Self.lineHeight)],
            breaks: [912...1080],
            position: .first
        )

        #expect(runs == [Run(top: 1080, bottom: frame.maxY, position: .first)])
    }

    @Test("A wrapped line across a break splits into two panels, square at the break")
    func wrappedLineSplits() {
        let frame = CGRect(x: 0, y: 870, width: 500, height: 1080 + Self.lineHeight - 870)
        let above = CGFloat(870)...(870 + Self.lineHeight)
        let below = CGFloat(1080)...(1080 + Self.lineHeight)

        let runs = CodeBlockLayoutFragment.panelRuns(frame: frame, lines: [above, below], breaks: [912...1080], position: .only)

        #expect(runs == [
            Run(top: 870, bottom: above.upperBound, position: .first),
            Run(top: 1080, bottom: frame.maxY, position: .last),
        ])
    }

    @Test("Seamless layout's 1pt break doesn't interrupt a panel")
    func hairlineBreakDoesNotSplit() {
        let frame = CGRect(x: 0, y: 900, width: 500, height: 913 + Self.lineHeight - 900)
        let runs = CodeBlockLayoutFragment.panelRuns(
            frame: frame,
            lines: [CGFloat(913)...(913 + Self.lineHeight)],
            breaks: [912...913],
            position: .middle
        )

        #expect(runs == [Run(top: frame.minY, bottom: frame.maxY, position: .middle)])
    }

    // MARK: The note's last line

    /// The last code fragment of `text`, laid out by TextKit.
    private static func lastCodeFragment(of text: String) throws -> (CodeBlockLayoutFragment, retaining: [AnyObject]) {
        final class Box { var value = "" }
        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 1400))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        textView.text = text
        coordinator.restyle(textView)

        let page = PageView(textView: textView)
        page.frame = CGRect(x: 0, y: 0, width: 872, height: 1200)
        window.addSubview(page)
        window.makeKeyAndVisible()
        page.layoutIfNeeded()
        textView.layoutIfNeeded()

        let manager = try #require(textView.textLayoutManager)
        let content = try #require(manager.textContentManager)
        var last: CodeBlockLayoutFragment?
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            if let code = fragment as? CodeBlockLayoutFragment { last = code }
            return true
        }
        return (try #require(last), [window, page, coordinator])
    }

    @Test("The empty line after a note's closing fence is outside the panel")
    func lineAfterClosingFence() throws {
        // TextKit puts the note's empty last line in the closing fence's
        // fragment, so the fragment is two lines tall.
        let (fence, retaining) = try Self.lastCodeFragment(of: "Intro\n```cpp\nint x;\n```\n")
        defer { withExtendedLifetime(retaining) {} }
        let lines = fence.textLineFragments
        try #require(lines.count == 2)
        let fenceBottom = fence.layoutFragmentFrame.minY + lines[0].typographicBounds.maxY

        let runs = fence.laidOutPanelRuns

        #expect(runs.count == 1)
        #expect(abs((runs.last?.bottom ?? 0) - fenceBottom) < 0.01,
                "panel ends at \(runs.last?.bottom ?? 0), the fence at \(fenceBottom)")
        #expect(runs.last?.position == .last)
    }

    @Test("An unclosed block at the end of a note still covers the line being typed")
    func lineAfterUnclosedBlock() throws {
        // The line after an unclosed block's last line is code: the block
        // runs to the end of the note.
        let (line, retaining) = try Self.lastCodeFragment(of: "Intro\n```cpp\nint x;\n")
        defer { withExtendedLifetime(retaining) {} }
        try #require(line.textLineFragments.count == 2)

        #expect(line.laidOutPanelRuns.last?.bottom == line.layoutFragmentFrame.maxY)
    }

    @Test("A closing fence with more after it is one line, as before")
    func closingFenceMidNote() throws {
        let (fence, retaining) = try Self.lastCodeFragment(of: "Intro\n```cpp\nint x;\n```\nAfter")
        defer { withExtendedLifetime(retaining) {} }

        #expect(fence.textLineFragments.count == 1)
        #expect(fence.laidOutPanelRuns == [Run(top: fence.layoutFragmentFrame.minY, bottom: fence.layoutFragmentFrame.maxY, position: .last)])
    }

    // MARK: Unchanged behaviour

    @Test("The block's outer edges keep their inset exactly", arguments: [2.0, 3.0] as [CGFloat])
    func outerEdgesStayInset(scale: CGFloat) {
        let frames = Self.frames(lines: 4, origin: 7.3)
        let rects = Self.panels(lines: 4, origin: 7.3, scale: scale)
        let inset = CodeBlockLayoutFragment.endInset

        #expect(rects.first!.minY == frames.first!.minY + inset)
        #expect(rects.last!.maxY == frames.last!.maxY - inset)
    }

    @Test("A one-paragraph block insets both ends")
    func singleParagraphBlock() {
        let frame = Self.frames(lines: 1, origin: 0)[0]
        let rect = Self.panels(lines: 1, origin: 0, scale: 2)[0]
        let inset = CodeBlockLayoutFragment.endInset

        #expect(rect.minY == frame.minY + inset)
        #expect(rect.maxY == frame.maxY - inset)
    }

    @Test("A nonsense scale still produces a usable rect", arguments: [0.0, -2.0] as [CGFloat])
    func degenerateScale(scale: CGFloat) {
        let rect = CodeBlockLayoutFragment.panelRect(
            frame: CGRect(x: 0, y: 10, width: 100, height: Self.lineHeight),
            position: .middle,
            scale: scale
        )

        #expect(rect.height > 0)
        #expect(rect.width == 100)
    }

    @Test("Pixel scale is read from the drawing context")
    func pixelScaleComesFromContext() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3

        var measured: CGFloat = 0
        _ = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format).image { ctx in
            measured = CodeBlockLayoutFragment.pixelScale(of: ctx.cgContext)
        }

        #expect(measured == 3)
    }
}

#endif
