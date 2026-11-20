#if canImport(UIKit)

import UIKit

/// What the page's zoom reads from, and asks of, the page it zooms.
@MainActor
protocol PageZoomHost: UIScrollView, UIGestureRecognizerDelegate {
    var textView: DocumentUITextView { get }
    var pageLayout: PageLayout { get }
    var displayScale: CGFloat { get }
    /// The text column, offered for fitting in a compact width only.
    var columnWidth: CGFloat? { get }
    /// Draws the page at `scale` in the current area.
    func apply(scale: CGFloat)
    /// Renders text at the density it is actually shown at.
    func matchRenderingScale()
}

/// The reader's zoom and the pinch that sets it (docs/refactor/2P-page.md,
/// 2P2). The zoom is relative to fitting the page's width to the area;
/// `PageView` still draws the page at the scale it works out
/// (`CanvasGeometry.displayScale`).
@MainActor
final class PageZoom {
    /// The reader's zoom, relative to fitting the page's width to the area.
    private(set) var zoom: CGFloat = 1

    let pinch = UIPinchGestureRecognizer()
    private var zoomAtPinchStart: CGFloat = 1
    private weak var host: PageZoomHost?

    init(host: PageZoomHost) {
        self.host = host
    }

    /// Whether a pinch is under way: the page isn't re-rendered at each step.
    var isPinching: Bool { pinch.state == .changed }

    /// Starts listening for the pinch on the page.
    func install() {
        guard let host else { return }
        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        pinch.delegate = host
        host.addGestureRecognizer(pinch)
    }

    /// Zooms to `newZoom`, keeping what's under `focus` under it.
    ///
    /// - Parameter focus: a point in the page view's visible area, in screen
    ///   points from its top left.
    func setZoom(_ newZoom: CGFloat, about focus: CGPoint) {
        guard let host else { return }
        let area = host.bounds.size
        guard area.width > 0, area.height > 0 else { return }

        let clamped = CanvasGeometry.clampedZoom(newZoom)
        let pageWidth = host.pageLayout.pageSize.width
        let next = CanvasGeometry.zoom(
            CanvasGeometry.Viewport(
                scale: host.displayScale,
                horizontalOffset: host.contentOffset.x,
                verticalOffset: host.textView.contentOffset.y
            ),
            to: CanvasGeometry.displayScale(
                areaWidth: area.width,
                pageWidth: pageWidth,
                columnWidth: host.columnWidth,
                zoom: clamped,
                gutter: CanvasGeometry.gutter(for: host.pageLayout.mode)
            ),
            about: focus,
            area: area,
            pageWidth: pageWidth,
            noteHeight: host.textView.contentSize.height
        )

        zoom = clamped
        host.apply(scale: next.scale)
        host.contentOffset.x = next.horizontalOffset
        host.textView.contentOffset.y = next.verticalOffset
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let host else { return }
        switch gesture.state {
        case .began:
            zoomAtPinchStart = zoom
            // Two fingers moving apart also look like a scroll. Stop both
            // scroll views taking a share of the gesture while it zooms.
            host.textView.panGestureRecognizer.isEnabled = false
        case .changed:
            let location = gesture.location(in: host)
            let focus = CGPoint(x: location.x - host.contentOffset.x, y: location.y - host.contentOffset.y)
            setZoom(zoomAtPinchStart * gesture.scale, about: focus)
        case .ended, .cancelled, .failed:
            host.textView.panGestureRecognizer.isEnabled = true
            host.matchRenderingScale()
        default:
            break
        }
    }
}

#endif
