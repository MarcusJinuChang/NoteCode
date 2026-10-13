//
//  HeadingMarkerDisplay.swift
//  NoteCode
//
//  A heading's hashes, drawn in the margin while the caret is on it.
//

#if canImport(UIKit)

import UIKit

/// Wiring for `HeadingLayoutFragment`, the way `CodeFenceDisplay.swift` wires
/// the fences. Same rule: this moves a redraw and nothing else. No layout and
/// no edit to the text storage, because either one lays out everything below
/// it again, and a hash that pushed its heading's text would leave ink over
/// the wrong words.
extension DocumentTextView.Coordinator {

    /// Works out which headings show their hashes and redraws the ones that
    /// changed. Called on every selection change and edit, so the common
    /// case, a caret that stays on the same line, compares two small values.
    func refreshHeadingMarkers(in textView: UITextView) {
        // A legacy note shows its hashes in the text; nothing to draw.
        let wanted: HeadingMarkerVisibility = rendersMarkdown
            ? HeadingMarkerVisibility.at(
                selection: textView.selectedRange,
                in: textView.textStorage.mutableString,
                codeRanges: codeRanges(in: textView.textStorage),
                mode: showMarkdown,
                isInk: editor?.mode == .ink
            )
            : .hidden
        guard wanted != headingVisibility else { return }

        let old = headingVisibility
        headingVisibility = wanted
        let everyHeading = wanted.showsEvery != old.showsEvery
        let changed = old.editing.symmetricDifference(wanted.editing)
        redrawHeadings(offsets: changed, all: everyHeading, in: textView)
    }

    /// The start of `fragment`'s paragraph in the note as it is now, found at
    /// draw time: an edit above moves a heading without touching its fragment.
    func offset(of fragment: NSTextLayoutFragment) -> Int? {
        guard let contentManager = fragment.textLayoutManager?.textContentManager else { return nil }
        return contentManager.offset(
            from: contentManager.documentRange.location,
            to: fragment.rangeInElement.location
        )
    }

    private func redrawHeadings(offsets: Set<Int>, all: Bool, in textView: UITextView) {
        guard all || !offsets.isEmpty,
              let layoutManager = textView.textLayoutManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange
        else { return }

        var dirty: [CGRect] = []
        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(viewport.endLocation) != .orderedDescending else { return false }
            guard let heading = fragment as? HeadingLayoutFragment else { return true }
            if all || self.offset(of: heading).map(offsets.contains) == true {
                let frame = heading.layoutFragmentFrame
                dirty.append(frame.union(heading.renderingSurfaceBounds.offsetBy(dx: frame.minX, dy: frame.minY)))
            }
            return true
        }

        let inset = textView.textContainerInset
        for rect in dirty {
            Self.redraw(
                fragmentViewsIn: textView,
                intersecting: rect.offsetBy(dx: inset.left, dy: inset.top).insetBy(dx: -2, dy: -2)
            )
        }
    }
}

#endif
