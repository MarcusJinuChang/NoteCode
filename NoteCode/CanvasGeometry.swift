//
//  CanvasGeometry.swift
//  NoteCode
//
//  How large the page is drawn, where it sits, and how zoom moves it.
//

import CoreGraphics

/// The page's on-screen geometry, as pure functions of the space it is given.
///
/// A note lays out at its pages' text width — see `PageLayout` — whatever iPad
/// it is on and however it is held. This decides only how large that is drawn:
/// a fit-to-width scale for the area, times the reader's zoom. Rotation, Split
/// View, moving the hotbar and pinching all change the scale, never where
/// lines wrap, so ink stays on the words it was drawn over.
nonisolated enum CanvasGeometry {

    /// The most fitting to width will enlarge a page.
    ///
    /// A portrait page fitted to a 13-inch iPad in landscape would be drawn at
    /// 1.5x, with body text near 26pt. Past this, extra width becomes margin;
    /// anyone who wants it larger can zoom.
    static let maximumFitScale: CGFloat = 1.25

    /// Zoom, relative to fitting the page's width. Out far enough to see a
    /// page and most of the next; in far enough to write between lines.
    static let minimumZoom: CGFloat = 0.5
    static let maximumZoom: CGFloat = 4

    /// Text is never rendered denser than this multiple of its drawn scale.
    ///
    /// Every line is its own view, as wide as the page. At 4x zoom on a 2x
    /// screen, full density is 5,400 by 180 pixels a line, 3.9MB; at this cap
    /// it is 2.2MB, and the difference is not visible at arm's length.
    static let maximumRenderingScale: CGFloat = 3

    // MARK: Room for the hotbar

    /// Room kept clear around the page for the hotbar.
    ///
    /// Both sides are always reserved, whichever edge the bar is on. The page's
    /// width is what sets its scale, so reserving only the docked side would
    /// resize the text every time the bar moved, and shift the page sideways
    /// besides. The bottom is reserved only while the bar is there: height
    /// never touches the scale, so it costs nothing to give it back.
    static func hotbarReserve(dock: HotbarDock, thickness: CGFloat) -> PageInsets {
        PageInsets(
            left: thickness,
            right: thickness,
            bottom: dock == .bottom ? thickness : 0
        )
    }

    // MARK: Scale

    /// Surround left showing either side of a sheet in print layout.
    ///
    /// Fitted edge to edge, sheets touch the sides of the area and read as one
    /// long slab with grey bars across it rather than as paper. The continuous
    /// modes fit edge to edge: there's no sheet edge for a border to show.
    static let printGutter: CGFloat = 24

    /// The scale that fits a page's width to the area, less a gutter each
    /// side, up to the ceiling.
    ///
    /// No floor. A landscape page in a portrait iPad fits at about 0.65x, and
    /// zoom is how it gets larger, rather than a floor that makes the page
    /// scroll sideways before the reader has asked for anything.
    static func fitScale(areaWidth: CGFloat, pageWidth: CGFloat, gutter: CGFloat = 0) -> CGFloat {
        let available = areaWidth - gutter * 2
        guard available > 0, pageWidth > 0 else { return 1 }
        return min(available / pageWidth, maximumFitScale)
    }

    /// The gutter a view mode fits its pages inside.
    static func gutter(for mode: PageViewMode) -> CGFloat {
        mode == .print ? printGutter : 0
    }

    static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, minimumZoom), maximumZoom)
    }

    /// How large the page is drawn: fitted, then zoomed.
    static func displayScale(areaWidth: CGFloat, pageWidth: CGFloat, zoom: CGFloat, gutter: CGFloat = 0) -> CGFloat {
        fitScale(areaWidth: areaWidth, pageWidth: pageWidth, gutter: gutter) * clampedZoom(zoom)
    }

    /// The density text is rendered at, for a scale on a screen.
    static func renderingScale(displayScale: CGFloat, screenScale: CGFloat) -> CGFloat {
        min(displayScale, maximumRenderingScale) * screenScale
    }

    /// The zoom PaperKit draws ink at, for a scale — see
    /// `DrawingCanvas.renderScale`.
    ///
    /// Never below 1. PaperKit takes input only inside the markup's bounds,
    /// which the canvas sets to the note's size times this, so below 1 they
    /// were narrower than the note: at 0.84x nothing could be drawn in the
    /// rightmost 134 points of a page, where the run and copy buttons sit
    /// (simulator, 25 September). Ink drawn at 1x and shown smaller is no
    /// softer for it.
    static func inkRenderScale(displayScale: CGFloat) -> CGFloat {
        max(1, min(displayScale, maximumRenderingScale))
    }

    // MARK: Frame

    /// The page's frame within its area, once drawn at `scale`.
    ///
    /// Centred when narrower than the area. When wider — zoomed in — it starts
    /// at the left edge and the area scrolls sideways.
    static func pageFrame(in area: CGSize, pageWidth: CGFloat, scale: CGFloat) -> CGRect {
        let width = pageWidth * scale
        return CGRect(
            x: max((area.width - width) / 2, 0),
            y: 0,
            width: width,
            height: area.height
        )
    }

    /// The page view's own bounds, in page points: always the page's width,
    /// and as tall as the area once the scale is undone.
    static func pageBounds(in area: CGSize, pageWidth: CGFloat, scale: CGFloat) -> CGSize {
        CGSize(width: pageWidth, height: scale > 0 ? area.height / scale : area.height)
    }

    // MARK: Zoom

    /// Where the page is scrolled to, and how large it is drawn.
    struct Viewport: Equatable, Sendable {
        var scale: CGFloat
        /// The area's sideways scroll, in screen points.
        var horizontalOffset: CGFloat
        /// The page's vertical scroll, in page points.
        var verticalOffset: CGFloat
    }

    /// The viewport after zooming to `scale`, keeping whatever was under
    /// `focus` under it — the point between two pinching fingers.
    ///
    /// - Parameters:
    ///   - focus: a point in the area, in screen points from its top left.
    ///   - noteHeight: how tall the note is, in page points, so the result
    ///     can't scroll past its end.
    static func zoom(
        _ viewport: Viewport,
        to scale: CGFloat,
        about focus: CGPoint,
        area: CGSize,
        pageWidth: CGFloat,
        noteHeight: CGFloat
    ) -> Viewport {
        guard viewport.scale > 0, scale > 0 else { return viewport }

        // The page point under the focus now.
        let oldFrame = pageFrame(in: area, pageWidth: pageWidth, scale: viewport.scale)
        let pageX = (focus.x + viewport.horizontalOffset - oldFrame.minX) / viewport.scale
        let pageY = viewport.verticalOffset + focus.y / viewport.scale

        // Put it back under the focus at the new scale.
        let newFrame = pageFrame(in: area, pageWidth: pageWidth, scale: scale)
        let maxHorizontal = max(newFrame.width - area.width, 0)
        let horizontal = newFrame.minX + pageX * scale - focus.x
        let maxVertical = max(noteHeight - area.height / scale, 0)
        let vertical = pageY - focus.y / scale

        return Viewport(
            scale: scale,
            horizontalOffset: min(max(horizontal, 0), maxHorizontal),
            verticalOffset: min(max(vertical, 0), maxVertical)
        )
    }
}

/// Insets without UIKit, so the geometry stays testable on its own.
nonisolated struct PageInsets: Equatable, Sendable {
    var left: CGFloat
    var right: CGFloat
    var bottom: CGFloat
}
