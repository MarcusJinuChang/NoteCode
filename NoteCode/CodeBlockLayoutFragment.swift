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

    // MARK: Page breaks

    /// A stretch of the fragment the panel covers, in container coordinates,
    /// with which of the block's ends it carries.
    struct PanelRun: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var position: CodeBlockPosition
    }

    /// Breaks shorter than this don't interrupt a panel. Seamless layout's
    /// 1pt break still pushes a line, and a code block reads better unbroken
    /// there; compressed and print layout's breaks are 24pt and more.
    static let minimumBreakHeight: CGFloat = 2

    /// The stretches a fragment's panel covers, split at page breaks.
    ///
    /// TextKit keeps a fragment's frame starting where its paragraph began and
    /// places a line pushed past an exclusion band further down inside it, so
    /// the frame spans the break. A panel drawn over the whole frame painted
    /// across the gap between two sheets in print layout. Splitting where a
    /// break lies above the first line, or between two lines of a wrapped
    /// one, keeps the panel on the page.
    ///
    /// Only the first run carries the block's top, and only the last its
    /// bottom: a code block continued over a page break is square at the
    /// break. With no break in the fragment this is one run over the whole
    /// frame, exactly as before.
    ///
    /// - Parameters:
    ///   - frame: the fragment's frame, in container coordinates.
    ///   - lines: each line's vertical extent, in container coordinates, in order.
    ///   - breaks: the page breaks' vertical extents, in container coordinates.
    static func panelRuns(
        frame: CGRect,
        lines: [ClosedRange<CGFloat>],
        breaks: [ClosedRange<CGFloat>],
        position: CodeBlockPosition
    ) -> [PanelRun] {
        let breaks = breaks.filter { $0.upperBound - $0.lowerBound >= minimumBreakHeight }

        /// Whether a page break sits in the space between `upper` and `lower`.
        func isBreak(from upper: CGFloat, to lower: CGFloat) -> Bool {
            breaks.contains { $0.lowerBound >= upper - 0.5 && $0.upperBound <= lower + 0.5 }
        }

        var bounds: [(top: CGFloat, bottom: CGFloat)] = []
        var runTop = frame.minY
        if let first = lines.first, isBreak(from: frame.minY, to: first.lowerBound) {
            runTop = first.lowerBound
        }
        for (upper, lower) in zip(lines, lines.dropFirst()) where isBreak(from: upper.upperBound, to: lower.lowerBound) {
            bounds.append((runTop, upper.upperBound))
            runTop = lower.lowerBound
        }
        bounds.append((runTop, frame.maxY))

        return bounds.enumerated().map { index, run in
            let roundsTop = index == 0 && position.roundsTop
            let roundsBottom = index == bounds.count - 1 && position.roundsBottom
            let runPosition: CodeBlockPosition = switch (roundsTop, roundsBottom) {
            case (true, true):   .only
            case (true, false):  .first
            case (false, true):  .last
            case (false, false): .middle
            }
            return PanelRun(top: run.top, bottom: run.bottom, position: runPosition)
        }
    }

    // MARK: Drawing

    private func drawPanel(at point: CGPoint, in context: CGContext) {
        let frame = layoutFragmentFrame
        let lines = textLineFragments.map { line in
            (frame.minY + line.typographicBounds.minY)...(frame.minY + line.typographicBounds.maxY)
        }
        let breaks = (textLayoutManager?.textContainer?.exclusionPaths ?? [])
            .map { $0.bounds.minY...$0.bounds.maxY }

        let runs = Self.panelRuns(frame: frame, lines: lines, breaks: breaks, position: position)
        let scale = Self.pixelScale(of: context)

        context.saveGState()
        context.setFillColor(fillColor.cgColor)

        for run in runs {
            // Span the container, not the text. `layoutFragmentFrame.width`
            // stops at the last glyph, which is precisely the ragged edge
            // being fixed here.
            let rect = Self.panelRect(
                frame: CGRect(
                    x: point.x,
                    y: point.y + (run.top - frame.minY),
                    width: panelWidth,
                    height: run.bottom - run.top
                ),
                position: run.position,
                scale: scale
            )

            var corners: UIRectCorner = []
            if run.position.roundsTop {
                corners.formUnion([.topLeft, .topRight])
            }
            if run.position.roundsBottom {
                corners.formUnion([.bottomLeft, .bottomRight])
            }

            let path: UIBezierPath = corners.isEmpty
                ? UIBezierPath(rect: rect)
                : UIBezierPath(
                    roundedRect: rect,
                    byRoundingCorners: corners,
                    cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
                  )
            context.addPath(path.cgPath)
        }

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
extension String {
    /// This text in Swift's own UTF-8 storage.
    ///
    /// `UITextView.text` hands back a String backed by the text storage's
    /// NSString, and every character read through it is a message send:
    /// parsing a 23KB note took about 3ms a keystroke in a Release build,
    /// most of it in `characterAtIndex:` (sampled on the simulator, 25
    /// September). Converting it first is one bulk copy.
    ///
    /// Parse and index the same converted text. Indices from one backing
    /// used on the other are reconciled on every use — see
    /// `DocumentStyler.applyStyling(to:source:blocks:previousSignatures:)`.
    nonisolated var nativeUTF8: String {
        var copy = self
        copy.makeContiguousUTF8()
        return copy
    }
}

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
            cachedCodeRanges = nil
            parseCount += 1
        }
        return cachedBlocks
    }

    private var cachedCodeRanges: [NSRange]?

    /// The code blocks' ranges, as UTF-16 ranges.
    ///
    /// Converted against the string the blocks were parsed from. Their
    /// indices belong to that instance, and converting them against another,
    /// even an equal one, forces index reconciliation on every use.
    func codeRanges(for source: String) -> [NSRange] {
        let blocks = blocks(for: source)
        if let cachedCodeRanges { return cachedCodeRanges }
        let parsed = cachedSource ?? source
        let ranges = blocks.filter(\.isCode).map { NSRange($0.range, in: parsed) }
        cachedCodeRanges = ranges
        return ranges
    }
}

#endif
