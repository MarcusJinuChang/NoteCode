//
//  ProseBlocks.swift
//  NoteCode
//
//  Obsidian's other blocks (text overhaul, phase 6): a quote's bar and a
//  horizontal rule, drawn by the fragments of their paragraphs.
//

#if canImport(UIKit)

import UIKit

/// The numbers a quote and a rule are made of.
nonisolated enum ProseBlockMetrics {

    /// How far each level of a quote sits in from the column. The bar is drawn
    /// in this room, so a quote lays its text out narrower and never leaves
    /// the page's column: nothing is drawn in the margin, and a wrapped
    /// line hangs where the first one starts.
    static let quoteIndent: CGFloat = 16

    /// The bar's width, and how far it sits from the left of its level's room.
    static let barWidth: CGFloat = 3
    static let barInset: CGFloat = 3

    /// The rule's thickness.
    static let ruleThickness: CGFloat = 1.5

    /// A quote line's paragraph style: the first line and the rest both start
    /// past the bars. The indent is the same at every text size; the line
    /// height is the note's spacing.
    static func quoteParagraphStyle(depth: Int, typography: NoteTypography = .standard) -> NSParagraphStyle {
        let style = typography.lineStyle(for: typography.prose)
        let indent = CGFloat(max(depth, 1)) * quoteIndent
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    /// The colour of a bar and of a rule: quiet on a white page and on a
    /// black one, and on paper (the PDF resolves it light).
    static var lineColour: UIColor { .systemGray3 }

    /// Where the stretches of a quote's bar are, in the fragment's own
    /// y-coordinates: one per run of lines that touch, so a quote that wraps
    /// across a page break is two bars and the gap is left clear.
    ///
    /// From the lines, never from the fragment's frame: a line pushed past a
    /// break stays in a fragment whose frame begins above it, so the frame
    /// spans the gap (AGENTS.md, Pages).
    static func barRuns(of lines: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var runs: [ClosedRange<CGFloat>] = []
        for line in lines.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = runs.last, line.lowerBound <= last.upperBound + 0.5 {
                runs[runs.count - 1] = last.lowerBound...max(last.upperBound, line.upperBound)
            } else {
                runs.append(line)
            }
        }
        return runs
    }
}

// MARK: - Quote

/// A quote line's paragraph, which draws its bar, or one for each level.
final class BlockquoteLayoutFragment: NSTextLayoutFragment {

    /// How many `>`s the line has.
    var depth = 1

    /// The column's left edge in the fragment's own coordinates, resolved at
    /// draw time for the reason `CodeBlockLayoutFragment.panelSpan` is: during
    /// the first layout pass the container reports a negative width.
    private var columnLeft: CGFloat {
        let padding = textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
        return padding - layoutFragmentFrame.minX
    }

    /// TextKit clips a fragment's drawing to this, and the default is sized
    /// to the glyphs, which start past the bars.
    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(
            CGRect(
                x: columnLeft,
                y: 0,
                width: CGFloat(max(depth, 1)) * ProseBlockMetrics.quoteIndent,
                height: layoutFragmentFrame.height
            )
        )
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        drawBars(of: textLineFragments, at: point, in: context)
    }

    /// The bars beside `lines`, which are this fragment's, over the lines
    /// themselves. The PDF draws a page's lines one at a time and calls this
    /// with the ones on the sheet.
    func drawBars(of lines: [NSTextLineFragment], at point: CGPoint, in context: CGContext) {
        let runs = ProseBlockMetrics.barRuns(of: lines.map { $0.typographicBounds.minY...$0.typographicBounds.maxY })
        guard !runs.isEmpty else { return }

        context.saveGState()
        context.setFillColor(ProseBlockMetrics.lineColour.cgColor)
        for level in 0..<max(depth, 1) {
            let x = point.x + columnLeft + CGFloat(level) * ProseBlockMetrics.quoteIndent + ProseBlockMetrics.barInset
            for run in runs {
                let rect = CGRect(x: x, y: point.y + run.lowerBound, width: ProseBlockMetrics.barWidth, height: run.upperBound - run.lowerBound)
                context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: ProseBlockMetrics.barWidth / 2).cgPath)
            }
        }
        context.fillPath()
        context.restoreGState()
    }
}

// MARK: - Rule

/// A rule's paragraph, which draws a line across the column through the
/// middle of its text, where the hidden dashes are.
final class RuleLayoutFragment: NSTextLayoutFragment {

    /// The column's left and right edges in the fragment's own coordinates
    /// (see `BlockquoteLayoutFragment.columnLeft`; the panel's `panelSpan`
    /// for the width).
    private var column: (left: CGFloat, right: CGFloat) {
        let container = textLayoutManager?.textContainer
        let padding = container?.lineFragmentPadding ?? 0
        let width = container?.size.width ?? 0
        let right = width > 0 ? width - padding : layoutFragmentFrame.maxX
        return (padding - layoutFragmentFrame.minX, right - layoutFragmentFrame.minX)
    }

    override var renderingSurfaceBounds: CGRect {
        let span = column
        return super.renderingSurfaceBounds.union(
            CGRect(x: span.left, y: 0, width: span.right - span.left, height: layoutFragmentFrame.height)
        )
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        drawRule(on: textLineFragments.first, at: point, in: context)
    }

    /// The line, through the middle of the x-height of `line`'s text. The
    /// PDF calls this with the paragraph's first line when it is on the sheet.
    func drawRule(on line: NSTextLineFragment?, at point: CGPoint, in context: CGContext) {
        guard let line else { return }
        let font = (textElement as? NSTextParagraph)?.attributedString
            .attribute(.font, at: 0, effectiveRange: nil) as? UIFont ?? DocumentStyler.proseFont
        let baseline = line.typographicBounds.minY + line.glyphOrigin.y
        let middle = baseline - font.xHeight / 2 - ProseBlockMetrics.ruleThickness / 2
        let span = column

        context.saveGState()
        context.setFillColor(ProseBlockMetrics.lineColour.cgColor)
        context.fill(CGRect(
            x: point.x + span.left,
            y: point.y + middle,
            width: span.right - span.left,
            height: ProseBlockMetrics.ruleThickness
        ))
        context.restoreGState()
    }
}

#endif
