import PaperKit
import UIKit

/// Whole-markup transforms for the ink pipeline: pure functions of a
/// `PaperMarkup`, out of `PageView` (docs/refactor/2P-page.md, 2P1).
/// Each walks or builds a `MarkupOrderedSet`, so the rules in AGENTS.md
/// apply: walk with `for`, build with one `append(contentsOf:)`.
enum InkMarkupTransforms {
    /// Where each element sits, by id.
    ///
    /// Walked with `for`, which uses the set's own iterator. `map` reads
    /// `MarkupOrderedSet` by index, and reading one element by index costs
    /// as much as `count` does, which grows with the set: this took 808ms
    /// for a note of 500 strokes and 10.6s for 2,000 (simulator, 10
    /// October), after every stroke, and drawing stalled. With `for` it
    /// takes 4.7ms at 500.
    ///
    /// With each shape, text box and image's `InkContent` fingerprint, taken
    /// in the same walk.
    static func frames(of markup: PaperMarkup) -> (frames: [MarkupOrderedSet.ElementID: CGRect], contents: [MarkupOrderedSet.ElementID: Int]) {
        var frames: [MarkupOrderedSet.ElementID: CGRect] = [:]
        var contents: [MarkupOrderedSet.ElementID: Int] = [:]
        for element in markup.subelements {
            frames[element.elementID] = element.renderFrame
            if let fingerprint = InkContent.fingerprint(of: element) {
                contents[element.elementID] = fingerprint
            }
        }
        return (frames, contents)
    }

    /// `markup` without the overflow of strokes drawn across a page break,
    /// for compressed and print layout. Taken out one by one: leaving an
    /// element out of an assigned set keeps it.
    static func withoutOverflow(_ markup: PaperMarkup) -> PaperMarkup {
        var overflow: [MarkupOrderedSet.ElementID] = []
        for element in markup.subelements where InkPages.isOverflow(element) {
            overflow.append(element.elementID)
        }
        guard !overflow.isEmpty else { return markup }
        var result = markup
        for id in overflow {
            result.subelements.removeElement(for: id)
        }
        return result
    }

    /// The ink with every element moved to the same place on its page in
    /// another layout, or `nil` when there's no such place — a different
    /// orientation wraps text at another width.
    ///
    /// Built as an array, appended to a new set in one go, and assigned once.
    /// Moving elements one at a time through `updateOrAppend` cost 3.3s for a
    /// thousand strokes (19 September). Appending them one at a time costs
    /// what the set's `count` does for each, which grows with it: a note of
    /// 5,000 strokes took 7 seconds to open. One `append(contentsOf:)` took
    /// 51ms (simulator, 10 October).
    static func convert(_ markup: PaperMarkup, from old: PageLayout, to new: PageLayout) -> PaperMarkup? {
        guard old.orientation == new.orientation else { return nil }
        guard old != new else { return markup }

        var elements: [any Markup] = []
        for element in markup.subelements {
            elements.append(InkCapture.moved(element, from: old, to: new))
        }
        var moved = MarkupOrderedSet()
        moved.append(contentsOf: elements)

        var result = markup
        result.subelements = moved
        return result
    }
}
