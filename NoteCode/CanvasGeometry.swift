//
//  CanvasGeometry.swift
//  NoteCode
//
//  Where the page sits, how big it is drawn, and how far it runs.
//

import CoreGraphics

/// The page's geometry, as pure functions of the space it is given.
///
/// Every note lays out at one width, `pageWidth`, whatever iPad it is on and
/// however it is held. Line breaks are a function of that width alone, so
/// rotation, Split View, and moving the hotbar change how large the page is
/// drawn, never where its lines wrap — and ink stays on the words it was drawn
/// over. See AGENTS.md, "Page geometry, orientation, and zoom".
nonisolated enum CanvasGeometry {

    /// The width every page lays out at, in page points.
    static let pageWidth: CGFloat = 700

    /// The display scale's range.
    ///
    /// Above the ceiling, extra width becomes margin instead of larger text:
    /// fitting a 13-inch iPad in landscape would draw body text at 1.75x.
    /// Below the floor, text stops being comfortably readable, and the page
    /// scrolls sideways instead of shrinking further.
    static let minimumScale: CGFloat = 0.75
    static let maximumScale: CGFloat = 1.25

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

    /// How large the page is drawn in an area this wide.
    ///
    /// A function of width only. Two iPads, or one iPad held two ways, get
    /// different scales over identical line breaks.
    static func displayScale(forAreaWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return min(max(width / pageWidth, minimumScale), maximumScale)
    }

    /// The page's frame within its area, once drawn at `scale`.
    ///
    /// Centred when narrower than the area. When wider — only below the
    /// minimum scale — it starts at the left edge and the area scrolls.
    static func pageFrame(in area: CGSize, scale: CGFloat) -> CGRect {
        let width = pageWidth * scale
        return CGRect(
            x: max((area.width - width) / 2, 0),
            y: 0,
            width: width,
            height: area.height
        )
    }

    /// The page view's own bounds, in page points: always `pageWidth` wide, and
    /// as tall as the area once the scale is undone.
    static func pageBounds(in area: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: pageWidth, height: scale > 0 ? area.height / scale : area.height)
    }

    // MARK: Running past the text

    /// The page's bottom inset, grown until the content reaches below the ink.
    ///
    /// The page scrolls as far as its text runs, so ink drawn below the last
    /// line would have nothing to scroll to. The inset makes up the difference.
    ///
    /// A function of its inputs only, and `textHeight` must exclude this inset.
    /// Deriving it from the content height as it stands would include last
    /// time's answer, and each layout pass would grow the page again.
    ///
    /// - Parameters:
    ///   - textHeight: how far the text runs, top inset included, bottom excluded.
    ///   - inkBottom: the lowest point of any ink, or `nil` for none.
    ///   - minimum: the inset with no ink below the text.
    ///   - room: space kept below the lowest ink, so there's somewhere to keep
    ///     writing.
    static func bottomInset(
        textHeight: CGFloat,
        inkBottom: CGFloat?,
        minimum: CGFloat,
        room: CGFloat
    ) -> CGFloat {
        guard let inkBottom else { return minimum }
        return max(minimum, inkBottom + room - textHeight)
    }
}

/// Insets without UIKit, so the geometry stays testable on its own.
nonisolated struct PageInsets: Equatable, Sendable {
    var left: CGFloat
    var right: CGFloat
    var bottom: CGFloat
}
