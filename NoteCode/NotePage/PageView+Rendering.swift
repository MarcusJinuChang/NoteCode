//
//  PageView+Rendering.swift
//  NoteCode
//
//  Text drawn at the density the page is shown at.
//

#if canImport(UIKit)

import UIKit

extension PageView {

    /// Renders text at the density it is actually shown at, up to a cap.
    ///
    /// A transform scales pixels that were drawn at the screen's own density,
    /// so text drawn at 1x and shown at 1.25x is soft. Raising the content
    /// scale makes TextKit draw it at the density it lands on. Newly created
    /// fragment views arrive at the default, which is why this also runs after
    /// every text view layout and every layout of the text on screen; it only
    /// touches a view whose value is wrong.
    ///
    /// The canvas is left out: PaperKit keeps its own views' scale, and draws
    /// ink at the density it's shown at by zooming instead — see
    /// `DrawingCanvas.renderScale`.
    func matchRenderingScale() {
        let value = CanvasGeometry.renderingScale(
            displayScale: displayScale,
            screenScale: traitCollection.displayScale
        )
        Self.setRenderingScale(value, in: textView, skipping: canvas)
        canvas.renderScale = CanvasGeometry.inkRenderScale(displayScale: displayScale)
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
