//
//  CodeSelectionHighlight.swift
//  NoteCode
//
//  Shows the selection over a code block's panel.
//

#if canImport(UIKit)

import UIKit

/// Why this exists: UIKit draws the selection highlight in a view at the back
/// of the text canvas, behind every fragment view (measured 7 Oct, the view
/// tree of a selected range: `_UITextSelectionHighlightView` is the first
/// subview, the `_UITextLayoutFragmentView`s come after). A code block's panel
/// is painted by its fragments, opaque, so it covers the highlight and a
/// selection inside a block showed nothing. Prose has no fill, so it was fine.
///
/// The panel can't go translucent: its seams and overhang are tuned for an
/// opaque fill (see `CodeBlockLayoutFragment.panelRect`), and a translucent one
/// would double-darken them. So `CodeBlockLayoutFragment` paints the selection
/// itself, right after its panel and behind its glyphs. A TextKit 2 rendering
/// attribute (`.backgroundColor`) was tried first and draws nothing in a custom
/// fragment: the pixels under a selected range didn't change.
///
/// Fragment views cache what they drew, so a selection change has to mark the
/// ones it touches as needing display. `invalidateRenderingAttributes` was
/// tried and never redrew them (the fragment's draw ran before the selection
/// was set and not after). `setNeedsDisplay` redraws without a layout pass, so
/// a drag across a note doesn't re-lay it out.
enum CodeSelectionHighlight {

    /// The alpha the tint is painted at. UIKit's own highlight is a tint at a
    /// similar strength; this is matched by eye against selected prose.
    static let alpha: CGFloat = 0.3

    /// What the fragment fills a selected stretch of a panel with.
    static var color: UIColor { UIColor.tintColor.withAlphaComponent(alpha) }

    /// The parts of `selection` that lie inside code blocks, fences included.
    ///
    /// Pure, so the rule is testable without a text view. A caret selects
    /// nothing, and a selection in prose gives nothing, since UIKit's own
    /// highlight already shows there.
    static func ranges(selection: NSRange, in codeRanges: [CodeRange]) -> [NSRange] {
        guard selection.length > 0 else { return [] }
        return codeRanges.compactMap { code in
            let overlap = NSIntersectionRange(selection, code.range)
            return overlap.length > 0 ? overlap : nil
        }
    }
}

extension DocumentTextView.Coordinator {

    /// Redraws the code blocks the selection has left or entered. Called on every selection change, so the common case, a caret
    /// with nothing painted before it, returns without touching TextKit.
    func updateCodeSelectionHighlight(in textView: UITextView) {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }

        let source = (textView.text ?? "").nativeUTF8
        let wanted = CodeSelectionHighlight.ranges(
            selection: textView.selectedRange,
            in: documentCache.codeRanges(for: source)
        )
        guard wanted != paintedCodeSelection else { return }

        let textRange = { Self.textRange($0, in: contentManager) }

        // Redraw what was selected (to take it off) and what is (to put it on).
        // The fragments read the selection themselves when they draw.
        var dirty = CGRect.null
        for range in paintedCodeSelection + wanted {
            guard let affected = textRange(range) else { continue }
            layoutManager.enumerateTextSegments(in: affected, type: .selection, options: []) { _, segment, _, _ in
                dirty = dirty.union(segment)
                return true
            }
        }
        if !dirty.isNull {
            // Segments are in the text container's coordinates.
            let inset = textView.textContainerInset
            dirty = dirty.offsetBy(dx: inset.left, dy: inset.top).insetBy(dx: -1, dy: -30)
            Self.redraw(fragmentViewsIn: textView, intersecting: dirty)
        }
        paintedCodeSelection = wanted
    }

    /// The painted selection as TextKit ranges, for a fragment to draw.
    func paintedTextRanges(in contentManager: NSTextContentManager?) -> [NSTextRange] {
        guard let contentManager else { return [] }
        return paintedCodeSelection.compactMap { Self.textRange($0, in: contentManager) }
    }

    private static func textRange(_ range: NSRange, in contentManager: NSTextContentManager) -> NSTextRange? {
        // An edit can shorten the text under what was painted.
        let document = contentManager.documentRange
        let length = contentManager.offset(from: document.location, to: document.endLocation)
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
        guard clamped.length > 0,
              let start = contentManager.location(document.location, offsetBy: clamped.location),
              let end = contentManager.location(start, offsetBy: clamped.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// Marks the fragment views overlapping `rect` as needing display. Matched
    /// by class name because UIKit's fragment views aren't public, as
    /// `CodeBlockPanelTests.upperLinesInFront` does; if the name changes this
    /// does nothing and the highlight appears on the next redraw instead.
    private static func redraw(fragmentViewsIn view: UIView, intersecting rect: CGRect) {
        func visit(_ subview: UIView) {
            if String(describing: type(of: subview)).contains("TextLayoutFragmentView"),
               subview.convert(subview.bounds, to: view).intersects(rect) {
                subview.setNeedsDisplay()
            }
            subview.subviews.forEach(visit)
        }
        view.subviews.forEach(visit)
    }
}

#endif
