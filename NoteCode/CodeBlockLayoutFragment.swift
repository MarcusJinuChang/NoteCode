//
//  CodeBlockLayoutFragment.swift
//  NoteCode
//
//  Draws a fenced code block as one continuous panel behind the text.
//

#if canImport(UIKit)

import UIKit

// MARK: - Position

/// Where one paragraph sits inside a fenced code block.
///
/// TextKit 2 lays out a paragraph at a time, so a five-line code block is five
/// separate fragments that each draw independently. Knowing which end of the
/// block a fragment is at is what lets them round only the outer corners and
/// join into a single panel rather than five stacked boxes.
nonisolated enum CodeBlockPosition: Equatable {
    /// The whole block is one paragraph.
    case only
    case first
    case middle
    case last

    var roundsTop: Bool { self == .first || self == .only }
    var roundsBottom: Bool { self == .last || self == .only }

    /// Locates `element` within `block`, both as UTF-16 ranges.
    /// Returns `nil` when the element isn't part of the block.
    static func of(element: NSRange, in block: NSRange) -> CodeBlockPosition? {
        let blockEnd = block.location + block.length
        guard element.location >= block.location, element.location < blockEnd else {
            return nil
        }

        let isFirst = element.location == block.location
        let isLast = element.location + element.length >= blockEnd

        switch (isFirst, isLast) {
        case (true, true):   return .only
        case (true, false):  return .first
        case (false, true):  return .last
        case (false, false): return .middle
        }
    }
}

// MARK: - Fragment

/// A layout fragment that paints a code-block panel before drawing its text.
///
/// This is the reason the editor needs TextKit 2 rather than an attributed
/// string alone: `.backgroundColor` is a per-glyph attribute, so it hugs the
/// end of each line and leaves a ragged right edge. Drawing at the fragment
/// level gives a rectangle spanning the full text container instead.
final class CodeBlockLayoutFragment: NSTextLayoutFragment {

    var position: CodeBlockPosition = .middle

    /// Width of the panel, resolved lazily.
    ///
    /// Deliberately *not* captured when the fragment is created: during the
    /// first layout pass the text view has no frame yet, so the container
    /// reports a width of -16 (zero bounds minus line-fragment padding).
    /// Reading it at draw time gets the settled value instead.
    private var panelWidth: CGFloat {
        let containerWidth = textLayoutManager?.textContainer?.size.width ?? 0
        return containerWidth > 0 ? containerWidth : layoutFragmentFrame.width
    }

    /// Expands the area this fragment is allowed to paint into.
    ///
    /// TextKit clips fragment drawing to these bounds, and the default is sized
    /// to the glyphs — so a full-width panel gets cropped back to the text
    /// width no matter how wide a rect is filled.
    override var renderingSurfaceBounds: CGRect {
        // The room above covers the overhang described in panelRect. TextKit
        // clips fragment drawing to these bounds, so without it the overhang is
        // trimmed and the seam comes back.
        //
        // Upward is the safe direction. TextKit 2 stacks fragment views with
        // each line in front of the line below it — measured, and held by
        // CodeBlockPanelTests.upperLinesInFront — so a panel reaching up lands
        // behind the line above, under its text and its descenders. Nothing is
        // added at the bottom: a panel reaching down would land in front of the
        // next line and paint over it.
        super.renderingSurfaceBounds.union(
            CGRect(
                x: 0,
                y: -Self.maximumOverhang,
                width: panelWidth,
                height: layoutFragmentFrame.height + Self.maximumOverhang
            )
        )
    }

    private let cornerRadius: CGFloat = 6

    /// Vertical breathing room at each end of a block.
    ///
    /// Without it, two code blocks on consecutive lines draw panels that touch,
    /// and three in a row read as a single block — you can't see where one ends
    /// and the next begins.
    static let endInset: CGFloat = 2
    private let fillColor = UIColor.secondarySystemBackground

    override func draw(at point: CGPoint, in context: CGContext) {
        drawPanel(at: point, in: context)
        super.draw(at: point, in: context)
    }

    /// Device pixels per point in the context being drawn into.
    ///
    /// Read from the transform rather than the screen so it stays right when the
    /// view is rendered somewhere other than the display.
    static func pixelScale(of context: CGContext) -> CGFloat {
        let scale = hypot(context.ctm.b, context.ctm.d)
        return scale > 0 ? scale : 1
    }

    /// How far an interior panel reaches above its fragment, in device pixels.
    static let overhangPixels: CGFloat = 2

    /// The most that overhang can be in points, which the rendering surface
    /// has to leave room for. Two points is two pixels even at 1x.
    static let maximumOverhang: CGFloat = 2

    /// The panel rectangle for one fragment.
    ///
    /// A code line is 20.021484375pt tall at body size, so fragment boundaries
    /// land partway through a device pixel rather than on the grid. Two
    /// fragments meeting inside one pixel each cover part of it, and two partial
    /// coverages composite to less than the fill: a hairline of the page showing
    /// through the block, every few lines. It is faint on a light background and
    /// obvious on a dark one.
    ///
    /// The cure is for the fragment *behind* to cover that pixel completely, so
    /// the one in front can be partial without the page showing through. Each
    /// line's view sits in front of the line below it, so the fragment behind is
    /// the lower one: an interior panel starts `overhangPixels` above its frame,
    /// underneath the line above. The bottom never moves — reaching down would
    /// paint in front of the next line's text.
    ///
    /// Whole pixels of overlap, not a round-up to the next pixel boundary. An
    /// earlier version rounded the bottom up to its own pixel grid, which works
    /// only while that grid is the screen's. Inside `PageView` the page is
    /// scaled by a transform, the fragment's grid sits some fraction off the
    /// screen's, and the edge is filtered as well; the round-up could leave no
    /// overlap on screen at all, and at 1.25x the seam came back.
    static func panelRect(
        frame: CGRect,
        position: CodeBlockPosition,
        scale: CGFloat
    ) -> CGRect {
        let scale = scale > 0 ? scale : 1
        let overhang = min(overhangPixels / scale, maximumOverhang)

        let top = position.roundsTop
            ? frame.minY + endInset
            : frame.minY - overhang

        let bottom = position.roundsBottom
            ? frame.maxY - endInset
            : frame.maxY

        return CGRect(
            x: frame.minX,
            y: top,
            width: frame.width,
            height: max(0, bottom - top)
        )
    }

    private func drawPanel(at point: CGPoint, in context: CGContext) {
        // Span the container, not the text. `layoutFragmentFrame.width` stops at
        // the last glyph, which is precisely the ragged edge being fixed here.
        let rect = Self.panelRect(
            frame: CGRect(
                x: point.x,
                y: point.y,
                width: panelWidth,
                height: layoutFragmentFrame.height
            ),
            position: position,
            scale: Self.pixelScale(of: context)
        )

        var corners: UIRectCorner = []
        if position.roundsTop {
            corners.formUnion([.topLeft, .topRight])
        }
        if position.roundsBottom {
            corners.formUnion([.bottomLeft, .bottomRight])
        }

        let path: UIBezierPath = corners.isEmpty
            ? UIBezierPath(rect: rect)
            : UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
              )

        context.saveGState()
        context.setFillColor(fillColor.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.restoreGState()
    }
}

// MARK: - Region cache

/// Avoids re-parsing the document once per visible fragment during layout.
///
/// TextKit 2 lays out lazily, so the fragment delegate is called for every
/// paragraph entering the viewport. Parsing each time would be O(document) per
/// fragment; caching against the source string makes it O(document) per edit.
final class DocumentCache {
    private var cachedSource: String?
    private var cachedBlocks: [BlockNode] = []

    /// How many times the parser actually ran. Exists so tests can prove the
    /// cache is doing its job — a keystroke should cost one parse, not several.
    private(set) var parseCount = 0

    func blocks(for source: String) -> [BlockNode] {
        if cachedSource != source {
            cachedSource = source
            cachedBlocks = DocumentParser.parse(source)
            parseCount += 1
        }
        return cachedBlocks
    }
}

#endif
