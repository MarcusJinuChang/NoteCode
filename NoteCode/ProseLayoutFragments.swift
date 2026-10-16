//
//  ProseLayoutFragments.swift
//  NoteCode
//
//  What a rendered note draws where its Markdown markers used to be: a
//  heading's hashes in the margin, and a checklist's boxes.
//

#if canImport(UIKit)

import UIKit

// MARK: - Which headings show their marker

/// Which headings draw their `#`s in the margin. Pure, like `FenceVisibility`.
///
/// **Drawn, never laid out.** The heading's text sits at the column edge
/// whether its hashes are showing or not; they are painted in the margin to
/// the left, so showing and hiding them moves nothing, and a stroke drawn
/// beside the heading stays beside it.
nonisolated struct HeadingMarkerVisibility: Equatable, Sendable {

    /// The start offset of each heading line the caret or a selection is on.
    var editing: Set<Int> = []

    /// Show Markdown: Always.
    var showsEvery = false

    static let hidden = HeadingMarkerVisibility()

    func shows(headingAt lineStart: Int) -> Bool {
        showsEvery || editing.contains(lineStart)
    }

    /// - Parameters:
    ///   - text: the note, so the lines under a selection can be found.
    ///   - codeRanges: the code blocks, whose lines are never headings.
    ///   - isInk: in ink mode nothing is being edited and the margin is left
    ///     bare, whatever the setting says: the page is for drawing on.
    static func at(
        selection: NSRange,
        in text: NSString,
        codeRanges: [CodeRange],
        mode: ShowMarkdown,
        isInk: Bool
    ) -> HeadingMarkerVisibility {
        guard !isInk else { return .hidden }
        var state = HeadingMarkerVisibility(showsEvery: mode == .always)

        for line in MarkdownFormatting.lines(touching: selection, in: text) {
            guard line.length > 0,
                  FenceVisibility.blockIndex(containing: line.location, in: codeRanges) == nil,
                  ProseLine.headingHashes(in: text, line: line) != nil
            else { continue }
            state.editing.insert(line.location)
        }
        return state
    }
}

/// Reading a single line of prose, for the fragments that decorate it.
///
/// Through `DocumentParser`, on the one line, so the fragments and the parser
/// can't disagree about what a heading or a checkbox is. A prefilter looks at
/// the first characters first: this runs for every paragraph TextKit lays out.
nonisolated enum ProseLine {

    /// The number of `#`s of a heading line, `nil` for anything else.
    static func headingHashes(in text: NSString, line: NSRange) -> Int? {
        guard line.length > 1, text.character(at: line.location) == 0x23 else { return nil }
        let content = text.substring(with: line)
        return DocumentParser.parse(content).first?.headingLevel
    }

    /// A checklist line's indentation (in UTF-16 units) and whether it is ticked.
    static func checkbox(in text: NSString, line: NSRange) -> (indent: Int, checked: Bool)? {
        var cursor = line.location
        let end = NSMaxRange(line)
        while cursor < end, text.character(at: cursor) == 0x20 || text.character(at: cursor) == 0x09 { cursor += 1 }
        guard cursor + 5 <= end else { return nil }
        let bullet = text.character(at: cursor)
        guard bullet == 0x2D || bullet == 0x2A || bullet == 0x2B, text.character(at: cursor + 1) == 0x20,
              text.character(at: cursor + 2) == 0x5B
        else { return nil }
        let content = text.substring(with: line)
        guard let block = DocumentParser.parse(content).first,
              case .checkbox(let checked)? = block.listMarker
        else { return nil }
        return (cursor - line.location, checked)
    }
}

// MARK: - Heading

/// A heading's paragraph, which also draws its hashes in the margin when
/// asked to.
final class HeadingLayoutFragment: NSTextLayoutFragment {

    /// How many `#`s the heading has.
    var hashes = 1

    /// Whether the hashes are showing now, asked at draw time: the answer
    /// follows the caret, and the fragment isn't laid out again when it does.
    var showsMarker: () -> Bool = { false }

    /// Gap between the hashes and the heading's text.
    static let gap: CGFloat = 8

    /// How far into the margin the fragment may paint: the page's margin plus
    /// the text container's line fragment padding.
    static let reach = PageLayout.margin + 5

    /// TextKit clips a fragment's drawing to this, and the default is sized to
    /// the glyphs, so without the margin added the hashes are cut off.
    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(
            CGRect(x: -Self.reach, y: 0, width: Self.reach, height: layoutFragmentFrame.height)
        )
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard showsMarker(), let line = textLineFragments.first else { return }

        // The heading's own font: the first character is a word joiner that
        // carries the marker run's attributes, which are the heading's.
        let font = (textElement as? NSTextParagraph)?.attributedString
            .attribute(.font, at: 0, effectiveRange: nil) as? UIFont ?? DocumentStyler.proseFont
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.secondaryLabel]
        let marker = String(repeating: "#", count: hashes) as NSString
        let width = marker.size(withAttributes: attributes).width

        // On the first line's baseline.
        let baseline = point.y + line.typographicBounds.minY + line.glyphOrigin.y
        let origin = CGPoint(x: point.x - Self.gap - width, y: baseline - font.ascender)

        UIGraphicsPushContext(context)
        marker.draw(at: origin, withAttributes: attributes)
        UIGraphicsPopContext()
    }
}

// MARK: - Checklist

/// A checklist item's paragraph, which draws its box.
final class ChecklistLayoutFragment: NSTextLayoutFragment {

    var isChecked = false

    /// Where the box's characters begin within the paragraph: after the
    /// indentation, the bullet and its space.
    var boxIndex = 2

    /// Whether the markers are collapsed. In a legacy note `- [ ]` is still
    /// on the page, and the box is drawn over its three glyphs; in a rendered
    /// one the box sits in the em space the markers were swapped for.
    var collapsed = true

    static let strokeWidth: CGFloat = 2
    static let cornerRadius: CGFloat = 6

    /// The box's rect in the fragment's own coordinates, and the full
    /// advance of the characters it stands on. `nil` when the line isn't laid
    /// out far enough to say.
    func boxRect() -> (box: CGRect, advance: CGRect)? {
        guard let line = textLineFragments.first,
              line.characterRange.length >= boxIndex + (collapsed ? 1 : 3)
        else { return nil }

        let font = (textElement as? NSTextParagraph)?.attributedString
            .attribute(.font, at: min(boxIndex, line.characterRange.length - 1), effectiveRange: nil) as? UIFont
            ?? DocumentStyler.proseFont
        let from = line.locationForCharacter(at: boxIndex).x
        let to = line.locationForCharacter(at: boxIndex + (collapsed ? 1 : 3)).x
        let side = (font.pointSize * 0.95).rounded()

        let baseline = line.typographicBounds.minY + line.glyphOrigin.y
        let centre = baseline - font.capHeight / 2
        let advance = CGRect(x: line.typographicBounds.minX + from, y: line.typographicBounds.minY,
                             width: to - from, height: line.typographicBounds.height)
        let box = CGRect(x: advance.midX - side / 2, y: centre - side / 2, width: side, height: side)
        return (box, advance)
    }

    override var renderingSurfaceBounds: CGRect {
        guard let rect = boxRect() else { return super.renderingSurfaceBounds }
        return super.renderingSurfaceBounds.union(rect.box.insetBy(dx: -2, dy: -2))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        drawBox(at: point, in: context)
    }

    /// The box alone, over its line. The PDF draws a page's lines one at a
    /// time and calls this with them.
    func drawBox(at point: CGPoint, in context: CGContext) {
        guard let rect = boxRect() else { return }
        let origin = CGPoint(x: point.x, y: point.y)
        let box = rect.box.offsetBy(dx: origin.x, dy: origin.y)

        context.saveGState()
        if !collapsed {
            // Over the `[ ]` that is still on the page.
            context.setFillColor(UIColor.systemBackground.cgColor)
            context.fill(rect.advance.offsetBy(dx: origin.x, dy: origin.y))
        }
        Self.drawBox(in: box, checked: isChecked, context: context)
        context.restoreGState()
    }

    /// An unchecked box is a 2pt `tertiaryLabel` outline with a 6pt radius; a
    /// checked one is the accent filled, with a white tick.
    static func drawBox(in rect: CGRect, checked: Bool, context: CGContext) {
        if checked {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            // The stored accent, not `tintColor`: that is the view's, and paper has none.
            context.setFillColor(AccentPalette.drawingColor().cgColor)
            context.addPath(path.cgPath)
            context.fillPath()

            let tick = UIBezierPath()
            tick.move(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.53))
            tick.addLine(to: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.70))
            tick.addLine(to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.32))
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(tick.cgPath)
            context.strokePath()
        } else {
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2), cornerRadius: cornerRadius)
            context.setStrokeColor(UIColor.tertiaryLabel.cgColor)
            context.setLineWidth(strokeWidth)
            context.addPath(path.cgPath)
            context.strokePath()
        }
    }
}

#endif
