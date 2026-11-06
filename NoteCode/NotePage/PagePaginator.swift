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
/// are already laid out costs about a millisecond for 40 pages, measured, since
/// an edit does not invalidate them. What was expensive was typesetting them
/// again, which exclusion paths made TextKit do on every keystroke.
///
/// **A paragraph taller than a page** keeps its place, and its page breaks
/// are exclusion paths on the container, set only for those paragraphs. A
/// note with one still pays for them on every keystroke.
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
        var edits: [(range: NSRange, push: CGFloat)] = []
        var tall: [(offset: Int, pages: [Int]?)] = []

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
            let naturalHeight = frame.height - applied
            guard let last = lines.last else {
                cursor += naturalHeight
                return true
            }
            let top = cursor + containerTop
            let lastBottom = top + (last.typographicBounds.maxY - applied)

            var push: CGFloat = 0
            var advance = naturalHeight
            var pages: [Int]?
            switch PageBreakRule.placement(top: top, lastLineBottom: lastBottom, layout: layout) {
            case .fits:
                break
            case .push(let distance):
                push = distance
            case .tall:
                let heights = lines.map { $0.typographicBounds.height }
                let placed = PageBreakRule.linePlacement(top: top, lineHeights: heights, layout: layout)
                pages = placed.pages
                // What follows the last line (spacing after) is unchanged.
                advance = (placed.bottom - top) + max(naturalHeight - (last.typographicBounds.maxY - applied), 0)
            }
            tall.append((start, pages))

            if abs(push - applied) > PageBreakRule.tolerance {
                let end = content.offset(from: documentStart, to: fragment.rangeInElement.endLocation)
                edits.append((NSRange(location: start, length: end - start), push))
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
                storage.edited(.editedAttributes, range: edit.range, changeInLength: 0)
            }
            storage.endEditing()
            table.isApplying = false
        }

        for entry in tall where table.tall[entry.offset] != entry.pages {
            table.set(tall: entry.pages, at: entry.offset)
        }
        let bandsChanged = applyBands(layout: layout, table: table, to: textView)
        if bandsChanged { changed = true }

        // Changed paragraphs are checked again from the first of them, once
        // TextKit has laid them out with their new pushes. New exclusion paths
        // change the height of the paragraphs they run through, wherever those
        // are, so the whole pass is checked.
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

    /// The break after each page a tall paragraph crosses, as the container's
    /// exclusion paths. Nothing else needs one.
    private func applyBands(layout: PageLayout, table: PagePushTable, to textView: DocumentUITextView) -> Bool {
        let pages = Set(table.tall.values.flatMap { $0 }).sorted()
        let rects = pages.map { layout.exclusionBand(afterPage: $0, containerTop: textView.textContainerInset.top) }
        let current = textView.textContainer.exclusionPaths.map(\.bounds)
        guard current != rects else { return false }
        textView.textContainer.exclusionPaths = rects.map { UIBezierPath(rect: $0) }
        return true
    }
}

#endif
