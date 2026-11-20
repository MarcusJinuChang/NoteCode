//
//  FenceDisplayController.swift
//  NoteCode
//
//  Which code blocks show their fences and which headings draw their
//  hashes, and what changed when the caret moved. Pulled out of
//  `DocumentTextView.Coordinator` (2T5); drawing stays with the Coordinator
//  (`CodeFenceDisplay.swift`, `HeadingMarkerDisplay.swift`), which asks this
//  what to redraw.
//

#if canImport(UIKit)

import UIKit

@MainActor
final class FenceDisplayController {

    /// Which blocks show their fences. See `CodeFenceDisplay.swift`.
    private(set) var fenceVisibility = FenceVisibility.away

    /// Which headings draw their hashes in the margin. See
    /// `HeadingMarkerDisplay.swift`.
    private(set) var headingVisibility = HeadingMarkerVisibility.hidden

    /// Works out which blocks are being edited. Nil when nothing changed,
    /// the common case: a caret that stays in the same block or in prose
    /// compares two small values. Otherwise the new state and the blocks
    /// whose drawing changed.
    func updateFences(
        selection: NSRange,
        ranges: [CodeRange],
        mode: ShowMarkdown,
        isInk: Bool
    ) -> (wanted: FenceVisibility, changed: Set<Int>)? {
        let wanted = FenceVisibility.at(selection: selection, in: ranges, mode: mode, isInk: isInk)
        guard wanted != fenceVisibility else { return nil }

        let old = fenceVisibility
        fenceVisibility = wanted
        let changed: Set<Int> = wanted.showsEveryFence == old.showsEveryFence
            ? old.editing.symmetricDifference(wanted.editing)
            : Set(ranges.indices)
        return (wanted, changed)
    }

    /// Takes in which headings are being edited. Nil when nothing changed;
    /// otherwise whether every heading changed and the offsets that did.
    func updateHeadings(_ wanted: HeadingMarkerVisibility) -> (all: Bool, changed: Set<Int>)? {
        guard wanted != headingVisibility else { return nil }

        let old = headingVisibility
        headingVisibility = wanted
        return (wanted.showsEvery != old.showsEvery, old.editing.symmetricDifference(wanted.editing))
    }
}

#endif
