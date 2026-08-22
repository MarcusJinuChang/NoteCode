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
enum CodeBlockPosition: Equatable {
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
        super.renderingSurfaceBounds.union(
            CGRect(x: 0, y: 0, width: panelWidth, height: layoutFragmentFrame.height)
        )
    }

    private let cornerRadius: CGFloat = 6
    private let fillColor = UIColor.secondarySystemBackground

    override func draw(at point: CGPoint, in context: CGContext) {
        drawPanel(at: point, in: context)
        super.draw(at: point, in: context)
    }

    private func drawPanel(at point: CGPoint, in context: CGContext) {
        // Span the container, not the text. `layoutFragmentFrame.width` stops at
        // the last glyph, which is precisely the ragged edge being fixed here.
        let width = panelWidth
        let rect = CGRect(
            x: point.x,
            y: point.y,
            width: width,
            height: layoutFragmentFrame.height
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
final class CodeRegionCache {
    private var cachedSource: String?
    private var cachedRegions: [Region] = []

    func regions(for source: String) -> [Region] {
        if cachedSource != source {
            cachedSource = source
            cachedRegions = FenceParser.parse(source)
        }
        return cachedRegions
    }
}

#endif
