//
//  CodeBlockRoom.swift
//  NoteCode
//
//  The space a code block takes around and inside its panel: how far the panel
//  reaches into the margins, the gaps between it and the text around it, and
//  the header its language and run and copy buttons sit in.
//

import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

/// The room around and inside a code block, in page points (roadmap step 10).
///
/// **Every vertical part of it is line height, never paragraph spacing.**
/// TextKit puts paragraph spacing outside the line it belongs to, so a page
/// break can fall inside it, and then the modes disagree: measured 16 Oct,
/// with 18pt of spacing above an opening fence, a block in a sweep of 25 sat
/// 13.3pt down its page in seamless and at the top of the page in compressed
/// and print, and every line after it moved with it, out from under its ink.
/// A line is pushed across a break whole, so space inside one lands on the
/// same page, at the same place, in every mode. The opening fence's line is
/// the gap above the panel and the header; the closing fence's is the footer
/// and the gap below.
///
/// **Sideways, nothing is laid out differently.** The panel reaches past the
/// text column into the page's margins, so the code keeps the prose column
/// and wraps where it would with no panel at all.
nonisolated enum CodeBlockRoom {

    /// How far the panel reaches past the text column on each side.
    static let outset: CGFloat = 14

    /// Space between the text above a block and its panel: the top of the
    /// opening fence's line.
    static let gapAbove: CGFloat = 12

    /// Space between a block's panel and the text below it: the bottom of
    /// the closing fence's line.
    static let gapBelow: CGFloat = 12

    /// The panel's top row, where the language and the run and copy buttons
    /// sit: the rest of the opening fence's line.
    static let headerHeight: CGFloat = 40

    static let cornerRadius: CGFloat = 10

    /// An unclosed block has no footer: its panel ends this far above the end
    /// of the line being typed, so a block typed straight above another
    /// doesn't run into it.
    static let unclosedInset: CGFloat = 2

    /// The header, from the opening fence's line: the line less the gap above.
    static func header(ofFenceLine line: CGRect) -> CGRect {
        CGRect(x: line.minX, y: line.minY + gapAbove, width: line.width, height: max(0, line.height - gapAbove))
    }

    /// The panel's left and right edges, for a text column.
    static func panelSpan(textLeft: CGFloat, textRight: CGFloat) -> (left: CGFloat, right: CGFloat) {
        (textLeft - outset, textRight + outset)
    }

    // MARK: Wrapped lines

    /// How many columns a wrapped line of code continues past its own line's
    /// indentation: room for the wrap mark (`CodeBlockLayoutFragment`), so a
    /// continuation never reads as a line of its own.
    ///
    /// A constant, not Settings › Code › Indent Width, which is per device:
    /// layout that followed it would wrap one note differently on two iPads,
    /// and move its ink.
    static let continuationColumns: CGFloat = 2

    /// No continuation starts further in than this, so a deeply indented
    /// line still has most of the page to wrap into.
    static let maximumContinuationColumns: CGFloat = 32

    /// TextKit's default tab stops are this far apart, and a code line's
    /// paragraph style keeps them.
    static let tabInterval: CGFloat = 28

    /// The width of a line's leading spaces and tabs, in a monospaced face
    /// whose characters are `advance` wide.
    static func leadingWidth(of line: some StringProtocol, advance: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        for character in line {
            switch character {
            case " ":  width += advance
            case "\t": width = (width / tabInterval).rounded(.down) * tabInterval + tabInterval
            default:   return width
            }
        }
        return width
    }

    /// Where a line's wrapped continuations start, from the text column's
    /// left edge: past its own indentation by `continuationColumns`.
    static func continuationIndent(leading: CGFloat, advance: CGFloat) -> CGFloat {
        min(leading + continuationColumns * advance, maximumContinuationColumns * advance)
    }
}

#if canImport(UIKit)

extension CodeBlockRoom {

    /// How one of a block's lines is set: a paragraph style that gives it its
    /// height, and how far its glyphs are lifted inside that height.
    struct LineStyle: Equatable {
        var paragraph: NSParagraphStyle
        var baselineOffset: CGFloat
    }

    /// The opening fence: the gap, then the header, with the fence's glyphs
    /// (shown while the block is edited) centred in the header where the
    /// language's name is otherwise drawn.
    ///
    /// TextKit's rule for a line with a fixed height and a raised baseline,
    /// measured 16 Oct: the extra height goes above the glyphs; and once the
    /// baseline is raised past the font's descent, the line loses its descent
    /// and ends at the baseline, the glyphs drawn `baselineOffset` above that.
    /// So the line is asked for its height plus the descent it will lose.
    static func openingFence(font: UIFont) -> LineStyle {
        let height = gapAbove + headerHeight
        let lift = max(headerHeight / 2 - font.capHeight / 2, descent(of: font))
        return LineStyle(paragraph: fixedHeight(height + descent(of: font)), baselineOffset: lift)
    }

    /// The closing fence: a footer, then the gap.
    ///
    /// The footer is shallower than a line of code, so the panel's padding
    /// below the last line matches the header's above the language (on
    /// screen, 16 Oct: a whole code line of footer looked bottom-heavy). Its
    /// glyphs, shown while the block is edited, are backticks, which sit
    /// high: their middle, about four fifths of the cap height above the
    /// baseline, is put at the footer's middle, which leaves the baseline
    /// below the footer and the backticks clear of the code above.
    static func closingFence(font: UIFont) -> LineStyle {
        let footer = footerHeight(font: font)
        let height = footer + gapBelow
        let baselineFromTop = footer / 2 + font.capHeight * 0.8
        let lift = max(height - baselineFromTop, descent(of: font))
        return LineStyle(paragraph: fixedHeight(height + descent(of: font)), baselineOffset: lift)
    }

    /// Where a caret on a fence's line may stand: in the header on an
    /// opening fence, in the footer on a closing one, a point clear of each
    /// edge. Nil for any other line. The footer is shallower than a caret for
    /// the code's font, so there the caret is the footer's height, not the
    /// font's, rather than reaching into the gap below the panel.
    static func caretRoom(onFenceLine line: CGRect, paragraph: NSParagraphStyle?, font: UIFont) -> CGRect? {
        guard let paragraph else { return nil }
        let room: CGRect
        if paragraph == openingFence(font: font).paragraph {
            room = header(ofFenceLine: line)
        } else if paragraph == closingFence(font: font).paragraph {
            room = CGRect(x: line.minX, y: line.minY, width: line.width, height: footerHeight(font: font))
        } else {
            return nil
        }
        return room.insetBy(dx: 0, dy: 1)
    }

    /// The panel's padding below the last line of code, in proportion to the
    /// code's size: 12pt beside 15pt code.
    static func footerHeight(font: UIFont) -> CGFloat {
        (font.pointSize * 0.8).rounded()
    }

    /// A line of code: as tall as a line of prose, though its type is smaller,
    /// its wrapped continuations starting `continuation` in from the text
    /// column (`continuationIndent`).
    static func codeLine(height: CGFloat, continuation: CGFloat = 0) -> NSParagraphStyle {
        let style = fixedHeight(height).mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = continuation
        return style
    }

    /// The width of one character of a monospaced face.
    static func advance(of font: UIFont) -> CGFloat {
        (" " as NSString).size(withAttributes: [.font: font]).width
    }

    static func descent(of font: UIFont) -> CGFloat {
        -font.descender
    }

    private static func fixedHeight(_ height: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return style
    }
}

#endif
