//
//  PagePaginator.swift
//  NoteCode
//
//  Works out which paragraphs start a page (F5), from where TextKit laid them.
//

#if canImport(UIKit)

import UIKit

/// Sets the pushes (`PagePushTable`) that keep every paragraph on one page.
///
/// **How.** From the first paragraph not yet known to be right — the one an
/// edit touched, or the top of a note in a layout it has no breaks for — it
/// walks the laid-out paragraphs to the end of the note with a running
/// position of its own: each paragraph's natural height is TextKit's, and its
/// place is where the one above it ended plus any push. A paragraph that would
/// end below its page's body gets a push of paragraph spacing to the next
/// body's top (`PageBreakRule`), through the content storage's delegate
/// (`BlankLineLayout`). Only a paragraph whose push changed is laid out again;
/// typing changes none unless a line wraps differently.
///
/// **To the end of the note, not as far as the reader has scrolled.** The
/// page count is the note's height, and TextKit estimates what it hasn't laid
/// out, so a count worked out from part of the note moved as the reader
/// scrolled (a 10-page note read 11, 9, 10 pages while it settled, and the
/// place it opened at moved with it). Reading the frames of paragraphs that
/// are already laid out is cheap, since an edit does not invalidate them:
/// about 4.3ms for the walk on 40 pages, so a keystroke at the top costs about
/// 8 times an unpaged one, about 0.11ms per page, and 22ms at 198 pages.
/// What was expensive was typesetting them again, which exclusion paths made
/// TextKit do on every keystroke. Opening a note still lays out the whole
/// note, as the paths did.
///
/// **A paragraph taller than a page** keeps its place, and each line of it
/// that would cross a break gets a gap above it in the layout's copy of the
/// paragraph (`PagePushTable.gaps`, laid in by `BlankLineLayout`), a
/// negative baseline offset that puts its glyphs at the next body's top.
/// (Unless its lines are a fixed height, a code line wrapped past a page:
/// an offset can't make those taller, so they keep exclusion paths.)
/// They used to be exclusion paths on the container, and with any path at
/// all TextKit laid out everything below an edit again: 55-90ms a keystroke
/// in a 40-page note (D9, docs/design/paged-typing-cost.md). A gap changes
/// no line's wrap and only its own paragraph's height.
@MainActor
final class PagePaginator {

    private weak var textView: DocumentUITextView?

    init(textView: DocumentUITextView) {
        self.textView = textView
    }

    /// How many passes in a row may change something before it stops.
    static let passLimit = 8

    /// One pass over the note from where it left off.
    ///
    /// - Returns: whether it changed anything, in which case the paragraphs it
    ///   changed are laid out again by the next pass, which checks them.
    @discardableResult
    func paginate(layout: PageLayout) -> Bool {
        guard let textView,
              let manager = textView.textLayoutManager,
              let content = manager.textContentManager as? NSTextContentStorage,
              let table = textView.blankLineLayout?.pushes
        else { return false }

        if table.layout != layout {
            table.layout = layout
            table.restart()
        }
        let storage = textView.textStorage
        if table.through >= storage.length {
            table.through = Int.max
        }
        if table.through == Int.max { return false }
        if table.changingPasses >= Self.passLimit { return false }

        let walkStart = table.through
        let containerTop = textView.textContainerInset.top
        let documentStart = content.documentRange.location
        guard let startLocation = content.location(documentStart, offsetBy: table.through) else { return false }

        var cursor: CGFloat = 0
        var started = false
        var edits: [(range: NSRange, push: CGFloat, gaps: [Int: PageLineGap])] = []
        var tall: [(range: NSRange, pages: [Int]?)] = []
        let bands = textView.textContainer.exclusionPaths.map(\.bounds)

        manager.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let start = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            let applied = Self.appliedPush(of: fragment)
            if !started {
                // A push is inside the fragment, at its top: the frame begins
                // where the paragraph would without it.
                cursor = frame.minY
                started = true
            }

            let lines = fragment.textLineFragments
            // The gaps it was laid out with, above some of its lines, are
            // inside it too: its own height is without them, measured afresh
            // from the lines as they are laid out now (`LineMeasure`).
            let measured = Self.hasLineGaps(fragment) || PageBreakRule.placement(
                top: cursor + containerTop,
                lastLineBottom: cursor + containerTop + (lines.last?.typographicBounds.maxY ?? 0) - applied,
                layout: layout
            ) == .tall ? measure(fragment) : nil
            let growth = measured.map { measure in lines.indices.map { lines[$0].typographicBounds.height - measure.natural[$0] } } ?? []
            // And the room TextKit skipped for the container's paths, in a
            // paragraph that has them: its lines are moved, not grown.
            let crossed = !bands.isEmpty && bands.contains { $0.minY < frame.maxY && $0.maxY > frame.minY }
            let gapTotal = growth.reduce(0, +) + (crossed ? Self.skipped(in: fragment) : 0)
            let naturalHeight = frame.height - applied - gapTotal
            guard let last = lines.last else {
                cursor += naturalHeight
                return true
            }
            let top = cursor + containerTop
            let lastBottom = top + (last.typographicBounds.maxY - applied - gapTotal)

            var push: CGFloat = 0
            var advance = naturalHeight
            var gaps: [Int: PageLineGap] = [:]
            var pages: [Int]?
            switch PageBreakRule.placement(top: top, lastLineBottom: lastBottom, layout: layout) {
            case .fits:
                break
            case .push(let distance):
                push = distance
            case .tall:
                let heights = measured?.natural ?? lines.map(\.typographicBounds.height)
                let placed = PageBreakRule.linePlacement(top: top, lineHeights: heights, layout: layout)
                if Self.hasFixedLineHeight(fragment) || Self.hasAttachment(fragment) {
                    // A code line or a formula's source, or a paragraph with
                    // an attachment in it: exclusion paths, as before D9
                    // (`PagePushTable.tall`).
                    pages = placed.pages
                } else {
                    for (index, gap) in placed.gaps {
                        // A gap above the first line is the paragraph's own
                        // push: the first line is where markers and boxes are
                        // drawn from.
                        if index == 0 { push = gap; continue }
                        let range = lines[index].characterRange
                        gaps[start + range.location] = PageLineGap(length: range.length, gap: gap, shift: gap + slack(of: lines[index], in: fragment))
                    }
                }
                // What follows the last line (spacing after) is unchanged.
                advance = (placed.bottom - top - push)
                    + max(naturalHeight - (last.typographicBounds.maxY - applied - gapTotal), 0)
            }

            let end = content.offset(from: documentStart, to: fragment.rangeInElement.endLocation)
            let range = NSRange(location: start, length: end - start)
            tall.append((range, pages))
            if abs(push - applied) > PageBreakRule.tolerance || !table.gaps(in: range, match: gaps) {
                edits.append((range, push, gaps))
            }
            cursor += push + advance
            return true
        }

        var changed = false
        if !edits.isEmpty {
            changed = true
            table.isApplying = true
            storage.beginEditing()
            for edit in edits {
                table.set(push: edit.push, at: edit.range.location)
                table.set(gaps: edit.gaps, in: edit.range)
                storage.edited(.editedAttributes, range: edit.range, changeInLength: 0)
            }
            storage.endEditing()
            table.isApplying = false
        }

        for entry in tall {
            table.set(tall: entry.pages, inParagraph: entry.range)
        }
        let bandsChanged = applyBands(layout: layout, table: table, to: textView)
        if bandsChanged { changed = true }

        // Changed paragraphs are checked again from the first of them, once
        // TextKit has laid them out with their new pushes and gaps. Neither
        // changes how a paragraph wraps, nor the height of any other. New
        // exclusion paths change the height of the paragraphs they run
        // through, wherever those are, so the whole pass is checked.
        var next = edits.first?.range.location ?? Int.max
        if bandsChanged { next = min(next, walkStart) }
        table.through = next
        table.changingPasses = changed ? table.changingPasses + 1 : 0
        return changed
    }

    /// The push a paragraph was laid out with.
    static func appliedPush(of fragment: NSTextLayoutFragment) -> CGFloat {
        guard let paragraph = fragment.textElement as? NSTextParagraph,
              paragraph.attributedString.length > 0,
              let push = paragraph.attributedString.attribute(.pagePush, at: 0, effectiveRange: nil) as? Double
        else { return 0 }
        return CGFloat(push)
    }

    /// The room TextKit left between a paragraph's lines to keep them out of
    /// the container's exclusion paths: each gap between two lines beyond the
    /// smallest one (line spacing), and any above the first beyond its
    /// spacing before (which holds the push). Main counted it in a tall
    /// paragraph's height, which was harmless while the paragraph stayed tall
    /// (only its line heights placed it) but misplaced it for a pass once it
    /// was cut below a page. Only for a paragraph a band crosses.
    static func skipped(in fragment: NSTextLayoutFragment) -> CGFloat {
        let lines = fragment.textLineFragments
        guard let first = lines.first else { return 0 }
        let string = (fragment.textElement as? NSTextParagraph)?.attributedString
        let style = (string?.length ?? 0) > 0 ? string?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
        let before = style?.paragraphSpacingBefore ?? 0
        var spaces: [CGFloat] = []
        for (above, below) in zip(lines, lines.dropFirst()) {
            spaces.append(below.typographicBounds.minY - above.typographicBounds.maxY)
        }
        // The space between two lines that no band moved: the paragraph's
        // line spacing, or less if its lines show less. Not the smallest
        // space alone, which a paragraph with one space between lines, and
        // that one a band's, would take for the normal one.
        let normal = max(min(style?.lineSpacing ?? 0, spaces.min() ?? 0), 0)
        var skipped = max(first.typographicBounds.minY - before, 0)
        if skipped < 0.5 { skipped = 0 }
        for space in spaces where space - normal > 0.5 { skipped += space - normal }
        return skipped
    }

    /// Whether a paragraph's lines are a fixed height (a code line, a display
    /// formula's source): a baseline offset can't make them taller.
    static func hasFixedLineHeight(_ fragment: NSTextLayoutFragment) -> Bool {
        guard let paragraph = fragment.textElement as? NSTextParagraph,
              paragraph.attributedString.length > 0,
              let style = paragraph.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        else { return false }
        return style.maximumLineHeight > 0
    }

    /// Whether a paragraph holds an attachment (an inline formula, in a
    /// rendered note). A baseline offset moves a line's text but not its
    /// attachment, whose descent takes up part of the offset: measured with
    /// a 44pt attachment, the line grew 6.19pt less than the offset, and
    /// with the offset made up for that, the text was drawn 6.19pt low. No
    /// one offset puts both the line and its glyphs where a path does, so
    /// such a paragraph keeps paths.
    static func hasAttachment(_ fragment: NSTextLayoutFragment) -> Bool {
        guard let paragraph = fragment.textElement as? NSTextParagraph else { return false }
        let string = paragraph.attributedString
        var found = false
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }

    /// The break after each page a fixed-height tall paragraph crosses
    /// (`PagePushTable.tall`), as the container's exclusion paths. A note
    /// with none has no paths, and costs a keystroke what an unpaged one
    /// does; a note with one pays for them on every keystroke.
    ///
    /// Only from entries that still start a paragraph: one an edit left in
    /// the middle of one (a join the walk has not reached yet) is dropped, so
    /// its band cannot outlive it.
    private func applyBands(layout: PageLayout, table: PagePushTable, to textView: DocumentUITextView) -> Bool {
        let text = textView.textStorage.string as NSString
        table.dropTall { !BlankLineLayout.startsParagraph($0, in: text) }
        let pages = Set(table.tall.values.flatMap { $0 }).sorted()
        let rects = pages.map { layout.exclusionBand(afterPage: $0, containerTop: textView.textContainerInset.top) }
        let current = textView.textContainer.exclusionPaths.map(\.bounds)
        guard current != rects else { return false }
        textView.textContainer.exclusionPaths = rects.map { UIBezierPath(rect: $0) }
        return true
    }

    /// A tall paragraph's lines as laid out now: each one's height without a
    /// gap (the slack is `slack(of:in:)`, for the lines that get one).
    struct LineMeasure {
        var natural: [CGFloat]
    }


    /// Measured every pass, never kept in the table: restyling (line
    /// spacing, the text size) changes them with no change of text.
    /// - **A fixed-height line** (code, a formula's source) never grows.
    /// - **A line with no offset** is its natural height.
    /// - **A line with one** is measured without it, laid out alone at the
    ///   same width (`alone(_:style:)`).
    /// - **The slack** of a line that gets a gap is measured the same way,
    ///   with a probe offset: a minimum line height (line spacing) or an
    ///   attachment's descent takes up part of an offset before the line
    ///   grows (measured: 17pt text, spacing 8, an offset of -100 grew the
    ///   line 91.98pt; a 44pt attachment, 6.19pt), so the offset is the gap
    ///   plus the slack.
    func measure(_ fragment: NSTextLayoutFragment) -> LineMeasure {
        let lines = fragment.textLineFragments
        let heights = lines.map(\.typographicBounds.height)
        let string = (fragment.textElement as? NSTextParagraph)?.attributedString ?? NSAttributedString()
        let style = string.length > 0 ? string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
        if (style?.maximumLineHeight ?? 0) > 0 {
            return LineMeasure(natural: heights)
        }
        var natural: [CGFloat] = []
        for (index, line) in lines.enumerated() {
            natural.append(line.pageLineShift > 0 ? alone(line, style: style).natural : heights[index])
        }
        return LineMeasure(natural: natural)
    }

    /// How much more than the gap the offset on `line` must be.
    func slack(of line: NSTextLineFragment, in fragment: NSTextLayoutFragment) -> CGFloat {
        let string = (fragment.textElement as? NSTextParagraph)?.attributedString ?? NSAttributedString()
        let style = string.length > 0 ? string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
        return alone(line, style: style).slack
    }

    /// What lines laid out alone measured, by the line: measured again only
    /// when the line or its style changes.
    private var measuredAlone: [NSAttributedString: (natural: CGFloat, slack: CGFloat)] = [:]

    /// The offset a probe lays in to measure a line's slack: more than any
    /// minimum line height or attachment takes up.
    static let probe: CGFloat = 200

    /// `line` laid out alone at the text view's width with its paragraph's
    /// style and the page break's offset taken back out: its height, and how
    /// much of an offset it takes up before it grows.
    private func alone(_ line: NSTextLineFragment, style: NSParagraphStyle?) -> (natural: CGFloat, slack: CGFloat) {
        let range = NSIntersectionRange(line.characterRange, NSRange(location: 0, length: line.attributedString.length))
        let plain = NSMutableAttributedString(attributedString: line.attributedString.attributedSubstring(from: range))
        let whole = NSRange(location: 0, length: plain.length)
        var shifts: [(NSRange, CGFloat)] = []
        plain.enumerateAttribute(.pageLineShift, in: whole) { value, run, _ in
            if let value = value as? Double, value > 0 { shifts.append((run, CGFloat(value))) }
        }
        for (run, shift) in shifts { Self.offset(plain, in: run, by: shift) }
        // Nor anything else of ours, which changes no line's height alone:
        // a push changing would otherwise measure every gap line again.
        for key in [NSAttributedString.Key.pageLineGap, .pageLineShift, .pagePush, .pageGap] {
            plain.removeAttribute(key, range: whole)
        }
        // Laid out as its paragraph's first line, which it isn't: no spacing
        // around it, and its paragraph's indent.
        let own = (style ?? .default).mutableCopy() as! NSMutableParagraphStyle
        own.paragraphSpacingBefore = 0
        own.paragraphSpacing = 0
        own.firstLineHeadIndent = own.headIndent
        plain.addAttribute(.paragraphStyle, value: own, range: whole)
        let key = NSAttributedString(attributedString: plain)
        if let known = measuredAlone[key] { return known }

        let natural = firstLineHeight(of: plain) ?? line.typographicBounds.height
        let probed = NSMutableAttributedString(attributedString: plain)
        Self.offset(probed, in: whole, by: -Self.probe)
        let grown = (firstLineHeight(of: probed) ?? natural + Self.probe) - natural
        let measured = (natural: natural, slack: max(Self.probe - grown, 0))
        if measuredAlone.count > 256 { measuredAlone = [:] }
        measuredAlone[key] = measured
        return measured
    }

    /// Adds `delta` to every `.baselineOffset` in `range`, dropping one
    /// that comes back to zero.
    private static func offset(_ string: NSMutableAttributedString, in range: NSRange, by delta: CGFloat) {
        var runs: [(NSRange, CGFloat)] = []
        string.enumerateAttribute(.baselineOffset, in: range) { value, run, _ in
            runs.append((run, CGFloat((value as? NSNumber)?.doubleValue ?? 0)))
        }
        for (run, offset) in runs {
            let new = offset + delta
            if abs(new) < 0.001 {
                string.removeAttribute(.baselineOffset, range: run)
            } else {
                string.addAttribute(.baselineOffset, value: new, range: run)
            }
        }
    }

    /// The height of `string`'s first line, laid out in a TextKit stack of
    /// its own at the text view's width: never the text view's, which it
    /// would lay out again. A new stack each time: one given a new string
    /// kept the last one's layout (measured), and the results are kept.
    private func firstLineHeight(of string: NSAttributedString) -> CGFloat? {
        let content = NSTextContentStorage()
        content.textStorage = NSTextStorage(attributedString: string)
        let manager = NSTextLayoutManager()
        content.addTextLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: 0, height: 0))
        if let textView, let viewContainer = textView.textLayoutManager?.textContainer {
            container.size = CGSize(width: viewContainer.size.width, height: 0)
            container.lineFragmentPadding = viewContainer.lineFragmentPadding
        }
        manager.textContainer = container
        var height: CGFloat?
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            height = fragment.textLineFragments.first?.typographicBounds.height
            return false
        }
        return height
    }

    /// The height a line's fonts and attachments ask for.
    static func contentHeight(of line: NSTextLineFragment, in string: NSAttributedString) -> CGFloat {
        let range = NSIntersectionRange(line.characterRange, NSRange(location: 0, length: string.length))
        guard range.length > 0 else { return 0 }
        var tallest: CGFloat = 0
        string.enumerateAttributes(in: range) { attributes, _, _ in
            if let font = attributes[.font] as? UIFont { tallest = max(tallest, font.lineHeight) }
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                tallest = max(tallest, attachment.bounds.height > 0 ? attachment.bounds.height : attachment.image?.size.height ?? 0)
            }
        }
        return tallest
    }

    /// Whether a paragraph was laid out with a gap above any of its lines:
    /// one attribute run to read for a paragraph with none.
    static func hasLineGaps(_ fragment: NSTextLayoutFragment) -> Bool {
        guard let paragraph = fragment.textElement as? NSTextParagraph else { return false }
        let string = paragraph.attributedString
        let whole = NSRange(location: 0, length: string.length)
        guard whole.length > 0 else { return false }
        var run = NSRange()
        return string.attribute(.pageLineGap, at: 0, longestEffectiveRange: &run, in: whole) != nil
            || run.length < whole.length
    }
}

#endif
