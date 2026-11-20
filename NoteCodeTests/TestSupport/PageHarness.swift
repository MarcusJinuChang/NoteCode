//
//  PageHarness.swift
//  NoteCodeTests
//
//  A `PageView` in a window, laid out: for the tests of page geometry, view
//  modes, scrolling and the ink shown on the page.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import UIKit
@testable import NoteCode

@MainActor
final class PageHarness {
    let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 1400, height: 1400))
    let page: PageView

    init(text: String = TestFixtures.longProse, area: CGSize = CGSize(width: 880, height: 1100), layout: PageLayout = PageLayout()) {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = text
        page = PageView(textView: textView)
        page.pageLayout = layout
        page.frame = CGRect(origin: .zero, size: area)
        window.addSubview(page)
        window.makeKeyAndVisible()
        layOut()
    }

    /// Enough passes for a page count change to settle: the pass that finds
    /// a new page adds its band, and the next lays text out against it.
    func layOut() {
        for _ in 0..<3 {
            page.setNeedsLayout()
            page.layoutIfNeeded()
            page.textView.setNeedsLayout()
            page.textView.layoutIfNeeded()
        }
    }

    func resize(to area: CGSize) {
        page.frame = CGRect(origin: .zero, size: area)
        layOut()
    }

    func switchTo(_ layout: PageLayout) {
        page.pageLayout = layout
        layOut()
    }

    // MARK: Ink

    /// Ink is a `PaperMarkup`, but strokes are easier to write as a
    /// `PKDrawing`, and PaperKit takes one wholesale.
    func setInk(_ drawing: PKDrawing) {
        var markup = PaperMarkup(bounds: CGRect(origin: .zero, size: CGSize(
            width: page.pageLayout.pageSize.width,
            height: 100_000
        )))
        markup.append(contentsOf: drawing)
        page.setInk(markup)
        layOut()
    }

    /// The elements on the canvas.
    var shown: [any Markup] {
        Array(page.canvas.markup.subelements)
    }

    /// Where the first stroke is shown, by its middle.
    var shownInkY: CGFloat? {
        page.canvas.markup.subelements.strokes.first?.renderBounds.midY
    }

    /// Inserts a shape the way the Insert menu does, at the middle of what is
    /// on screen.
    func insertShape(_ type: ShapeConfiguration.Shape = .rectangle) {
        let edit = MarkupEditViewController(supportedFeatureSet: .latest)
        page.insertIntoInk(extent: InkInsertion.shapeExtent) {
            page.canvas.controller.markupEditViewController(edit, insertNewShape: type)
        }
        layOut()
    }

    // MARK: Text

    /// Every line, in note coordinates, laid out to the end.
    var lines: [(range: NSRange, frame: CGRect)] {
        page.paginate()
        let textView = page.textView
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager
        else { return [] }

        let top = textView.textContainerInset.top
        var lines: [(NSRange, CGRect)] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let origin = fragment.layoutFragmentFrame.origin
            for line in fragment.textLineFragments {
                let range = NSRange(location: start + line.characterRange.location, length: line.characterRange.length)
                lines.append((range, line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y + top)))
            }
            return true
        }
        return lines
    }

    /// The character that starts the first line reaching below the top of
    /// the view, found the way a reader would: the first line whose bottom
    /// is past the edge. Looking up whatever sits at the edge instead is
    /// ambiguous when the edge is in a margin or a page break.
    var lineAtTop: Int? {
        let textView = page.textView
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager
        else { return nil }

        let edge = textView.contentOffset.y - textView.textContainerInset.top
        let documentStart = content.documentRange.location
        let from = manager.textViewportLayoutController.viewportRange?.location ?? documentStart

        var found: Int?
        manager.enumerateTextLayoutFragments(from: from, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard let line = fragment.textLineFragments.first(where: { frame.minY + $0.typographicBounds.maxY > edge }) else {
                return true
            }
            found = content.offset(from: documentStart, to: fragment.rangeInElement.location) + line.characterRange.location
            return false
        }
        return found
    }
}

#endif
