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

        let containerTop = textView.textContainerInset.top
        let documentStart = content.documentRange.location
        guard let startLocation = content.location(documentStart, offsetBy: table.through) else { return false }

        var cursor: CGFloat = 0
        var started = false
        var edits: [(range: NSRange, push: CGFloat, gaps: [Int: PageLineGap])] = []

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
            // inside it too: its own height is without them.
            let appliedGaps = Self.hasLineGaps(fragment) ? lines.map(\.pageLineGap) : []
            let gapTotal = appliedGaps.reduce(0, +)
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
            switch PageBreakRule.placement(top: top, lastLineBottom: lastBottom, layout: layout) {
            case .fits:
                break
            case .push(let distance):
                push = distance
            case .tall:
                let heights = lines.enumerated().map { index, line in
                    line.typographicBounds.height - (appliedGaps.isEmpty ? 0 : appliedGaps[index])
                }
                let placed = PageBreakRule.linePlacement(top: top, lineHeights: heights, layout: layout)
                for (index, gap) in placed.gaps {
                    // A gap above the first line is the paragraph's own push:
                    // the first line is where markers and boxes are drawn from.
                    if index == 0 { push = gap; continue }
                    let range = lines[index].characterRange
                    gaps[start + range.location] = PageLineGap(length: range.length, gap: gap)
                }
                // What follows the last line (spacing after) is unchanged.
                advance = (placed.bottom - top - push)
                    + max(naturalHeight - (last.typographicBounds.maxY - applied - gapTotal), 0)
            }

            let end = content.offset(from: documentStart, to: fragment.rangeInElement.endLocation)
            let range = NSRange(location: start, length: end - start)
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

        // Changed paragraphs are checked again from the first of them, once
        // TextKit has laid them out with their new pushes and gaps. Neither
        // changes how a paragraph wraps, nor the height of any other.
        table.through = edits.first?.range.location ?? Int.max
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
