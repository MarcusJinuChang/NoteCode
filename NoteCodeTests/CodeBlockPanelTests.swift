//
//  CodeBlockPanelTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

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

    // MARK: The bug being fixed

    @Test("Fragment boundaries fall mid-pixel to begin with", arguments: [2.0, 3.0] as [CGFloat])
    func boundariesAreNotPixelAligned(scale: CGFloat) {
        let boundaries = (1..<6).map { CGFloat($0) * Self.lineHeight }
        #expect(boundaries.contains { ($0 * scale) != ($0 * scale).rounded() })
    }

    @Test(
        "Consecutive panels never leave a gap",
        arguments: [2.0, 3.0] as [CGFloat], [0.0, 12.0, 0.5, 7.3] as [CGFloat]
    )
    func noSeamBetweenFragments(scale: CGFloat, origin: CGFloat) {
        let rects = Self.panels(lines: 6, origin: origin, scale: scale)

        for (upper, lower) in zip(rects, rects.dropFirst()) {
            #expect(
                upper.maxY >= lower.minY,
                "gap of \(lower.minY - upper.maxY)pt at scale \(scale), origin \(origin)"
            )
        }
    }

    @Test("An interior fragment ends on a whole device pixel", arguments: [2.0, 3.0] as [CGFloat])
    func interiorBottomsArePixelAligned(scale: CGFloat) {
        let rects = Self.panels(lines: 6, origin: 7.3, scale: scale)

        for rect in rects.dropLast() {
            #expect((rect.maxY * scale).rounded() == rect.maxY * scale)
        }
    }

    // MARK: The regression guard

    @Test(
        "A panel never reaches above its own fragment",
        arguments: [2.0, 3.0] as [CGFloat], [0.0, 0.5, 7.3] as [CGFloat]
    )
    func neverPaintsUpward(scale: CGFloat, origin: CGFloat) {
        // This is the one that matters. A panel drawn above its own fragment
        // lands on the line above, which has already drawn its text, and eats
        // the tail of any descender there. Growing the panel downward instead
        // is harmless: the fragment below has not drawn yet and will cover it.
        let frames = Self.frames(lines: 6, origin: origin)
        let rects = Self.panels(lines: 6, origin: origin, scale: scale)

        for (frame, rect) in zip(frames, rects) {
            #expect(rect.minY >= frame.minY, "panel starts \(frame.minY - rect.minY)pt above its fragment")
        }
    }

    @Test("A panel overhangs its fragment by at most one pixel", arguments: [2.0, 3.0] as [CGFloat])
    func overhangIsBounded(scale: CGFloat) {
        let frames = Self.frames(lines: 6, origin: 7.3)
        let rects = Self.panels(lines: 6, origin: 7.3, scale: scale)

        for (frame, rect) in zip(frames, rects) {
            #expect(rect.maxY - frame.maxY <= 1 / scale + .ulpOfOne)
        }
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
