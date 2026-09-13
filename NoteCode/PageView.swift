//
//  PageView.swift
//  NoteCode
//
//  The page: one fixed-width text view, drawn at whatever scale fits.
//

#if canImport(UIKit)

import PencilKit
import UIKit

/// Hosts the editor at `CanvasGeometry.pageWidth` and draws it at the display
/// scale for the space available.
///
/// The text view still scrolls itself, and the scale is a transform on it.
/// The phase plan had a non-scrolling text view inside an outer zoom scroll
/// view instead. Measured on 12 September 2026, that makes TextKit 2's
/// viewport the entire document: a 500-line note cost 477ms per keystroke
/// against 11ms, and a 2000-line note 5.5 seconds. A transform leaves the
/// viewport alone — the same note measured 9ms.
///
/// This view scrolls only sideways, and only when the page is wider than it
/// is, below the minimum scale.
final class PageView: UIScrollView {

    let textView: DocumentUITextView

    /// The ink layer. A subview of the text view's content, so it scrolls with
    /// the text and is scaled by the same transform, with no code to keep the
    /// two in step.
    let canvas = PKCanvasView()

    /// The scale the page is drawn at right now.
    private(set) var displayScale: CGFloat = 1

    /// The lowest point of any ink, cached so a layout pass — which scrolling
    /// runs every frame — doesn't walk the strokes.
    private var inkBottom: CGFloat?

    /// Bottom inset with no ink below the text.
    static let minimumBottomInset: CGFloat = 12

    /// Page left free below the lowest ink, so there's room to keep writing.
    static let roomBelowInk: CGFloat = 200

    init(textView: DocumentUITextView) {
        self.textView = textView
        super.init(frame: .zero)

        // Neither scroll view should invent insets of its own. SwiftUI already
        // keeps this view clear of the keyboard and the safe area.
        contentInsetAdjustmentBehavior = .never
        textView.contentInsetAdjustmentBehavior = .never

        isDirectionalLockEnabled = true
        alwaysBounceVertical = false
        showsVerticalScrollIndicator = false
        addSubview(textView)

        // The line width is set here, never inferred. Left tracking the view,
        // a text view whose width is first set while it is scaled below 1x
        // sizes its container from the shrunken frame: at 0.974x the page
        // wrapped at 634pt instead of 652pt, and portrait and landscape broke
        // lines differently. Caught by PageViewTests.identicalLineBreaks.
        textView.textContainer.widthTracksTextView = false
        pinLineWidth()

        // A drawing surface, not a second scroll view competing for the pan.
        canvas.isScrollEnabled = false
        // Transparent, or it paints white over every word underneath.
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Text owns input until the toggle hands it over.
        canvas.isUserInteractionEnabled = false
        textView.addSubview(canvas)

        textView.addLayoutObserver { [weak self] in
            self?.textViewDidLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let area = bounds.size
        guard area.width > 0, area.height > 0 else { return }

        let scale = CanvasGeometry.displayScale(forAreaWidth: area.width)
        let frame = CanvasGeometry.pageFrame(in: area, scale: scale)
        let pageSize = CanvasGeometry.pageBounds(in: area, scale: scale)

        if scale != displayScale || textView.transform.a != scale {
            displayScale = scale
            textView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }

        // Size only, never origin: a scroll view's bounds origin is its scroll
        // position, and that is in page points, so it survives a scale change
        // untouched. The line at the top stays at the top through a rotation.
        if textView.bounds.size != pageSize {
            textView.bounds.size = pageSize
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        if textView.center != center {
            textView.center = center
        }

        let content = CGSize(width: max(area.width, frame.width), height: area.height)
        if contentSize != content {
            contentSize = content
        }

        matchRenderingScale()
    }

    /// Sets the text container to the page width less the page's side margins.
    private func pinLineWidth() {
        let inset = textView.textContainerInset
        let width = CanvasGeometry.pageWidth - inset.left - inset.right
        if textView.textContainer.size.width != width {
            textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        }
    }

    /// Runs after every layout pass of the text view, which includes every
    /// scroll and every edit.
    private func textViewDidLayout() {
        sizeCanvas()
        matchRenderingScale()
    }

    // MARK: Ink

    /// Call after the drawing changes, so the page can grow to reach it.
    func drawingDidChange() {
        inkBottom = canvas.drawing.strokes.isEmpty ? nil : canvas.drawing.bounds.maxY
        textView.setNeedsLayout()
    }

    /// Extends the page below its text to reach the lowest ink, and stretches
    /// the canvas over all of it.
    private func sizeCanvas() {
        var inset = textView.textContainerInset
        // Excludes the bottom inset on purpose. Including it would feed this
        // pass's answer into the next, and grow the page on every layout.
        let textHeight = textView.contentSize.height - inset.bottom

        let bottom = CanvasGeometry.bottomInset(
            textHeight: textHeight,
            inkBottom: inkBottom,
            minimum: Self.minimumBottomInset,
            room: Self.roomBelowInk
        )
        if abs(inset.bottom - bottom) > 0.5 {
            inset.bottom = bottom
            textView.textContainerInset = inset
        }

        // From the inset just worked out, not from `contentSize`, which doesn't
        // reflect a new inset until the next layout pass — the canvas would
        // trail the page it is meant to cover by a pass.
        //
        // At least a screen tall, so a short note can still be drawn on below
        // its last line.
        let frame = CGRect(
            x: 0,
            y: 0,
            width: textView.bounds.width,
            height: max(textHeight + bottom, textView.bounds.height)
        )
        if canvas.frame != frame {
            canvas.frame = frame
        }
    }

    // MARK: Rendering

    /// Renders text at the density it is actually shown at.
    ///
    /// A transform scales pixels that were drawn at the screen's own density,
    /// so text drawn at 1x and shown at 1.25x is soft. Raising the content
    /// scale makes TextKit draw it at the density it lands on. Newly created
    /// fragment views arrive at the default, which is why this also runs after
    /// every text view layout; it only touches a view whose value is wrong.
    ///
    /// The canvas is left out. PencilKit manages its own rendering, and
    /// whether it needs the same treatment is for the toggle step, when there
    /// is ink on screen to look at.
    private func matchRenderingScale() {
        Self.setRenderingScale(displayScale * traitCollection.displayScale, in: textView, skipping: canvas)
    }

    private static func setRenderingScale(_ value: CGFloat, in view: UIView, skipping excluded: UIView) {
        guard view !== excluded else { return }
        if view.contentScaleFactor != value {
            view.contentScaleFactor = value
        }
        for subview in view.subviews {
            setRenderingScale(value, in: subview, skipping: excluded)
        }
    }
}

#endif
