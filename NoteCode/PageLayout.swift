//
//  PageLayout.swift
//  NoteCode
//
//  Where pages fall in a note, in each of the three ways it can be viewed.
//

import CoreGraphics

/// Which way up a note's pages are. A property of the note, like paper.
nonisolated enum PageOrientation: String, CaseIterable, Sendable {
    case portrait
    case landscape

    static let `default` = PageOrientation.portrait
}

/// How pages are shown. A preference about viewing, not a property of a note,
/// so it follows the device rather than the page.
nonisolated enum PageViewMode: String, CaseIterable, Sendable {
    /// One continuous surface. Page breaks exist but aren't drawn.
    case seamless
    /// Continuous, with a dashed line where one page ends and the next begins.
    case compressed
    /// Separate sheets of paper, margins and all, the way they would print.
    case print

    static let `default` = PageViewMode.seamless
    static let defaultsKey = "pageViewMode"
}

/// The geometry of a paged note, as pure functions.
///
/// **One pagination, three presentations.** Every mode breaks pages at the
/// same lines: each page holds a body `bodyHeight` tall, and text flows around
/// a band between one body and the next. The modes differ only in how tall
/// that band is — a sheet's two margins and the gap between sheets in print
/// layout, a narrow strip in compressed, a hairline in seamless. Because
/// a point's position *within its page's body* is the same in every mode, ink
/// converts between modes by page (`convert`) and stays on the words it was
/// drawn over. Pagination that differed by mode would make that impossible.
///
/// Units are page points: US Letter at 96 per inch, the CSS convention. At
/// that size the editor's 17pt body text prints at 12.75pt, a normal printed
/// size, because a page 816 wide prints 612 points wide.
nonisolated struct PageLayout: Equatable, Sendable {

    var orientation: PageOrientation
    var mode: PageViewMode

    init(orientation: PageOrientation = .default, mode: PageViewMode = .default) {
        self.orientation = orientation
        self.mode = mode
    }

    // MARK: Paper

    static let unitsPerInch: CGFloat = 96

    /// US Letter. A4 would be one more case here; nothing else depends on it.
    static let paperInches = CGSize(width: 8.5, height: 11)

    /// Three-quarters of an inch on every side.
    static let margin: CGFloat = 72

    /// A sheet, in page points.
    var pageSize: CGSize {
        let portrait = CGSize(
            width: Self.paperInches.width * Self.unitsPerInch,
            height: Self.paperInches.height * Self.unitsPerInch
        )
        return orientation == .portrait
            ? portrait
            : CGSize(width: portrait.height, height: portrait.width)
    }

    /// The width lines wrap at. Fixed per orientation, so line breaks never
    /// depend on the device, its orientation, the zoom, or the view mode.
    var textWidth: CGFloat { pageSize.width - Self.margin * 2 }

    /// How much of a page text can fill. The same in every mode, which is
    /// what makes pagination the same in every mode.
    var bodyHeight: CGFloat { pageSize.height - Self.margin * 2 }

    // MARK: Between pages

    /// Space between sheets in print layout.
    static let printSheetGap: CGFloat = 24

    /// The strip a compressed page break occupies, dashed line in its middle.
    static let compressedGap: CGFloat = 24

    /// A seamless page break. Not zero: a band with no height pushes no line,
    /// and a line left straddling the break would paginate differently here
    /// than in the other modes. One point is enough to push it, and too little
    /// to see.
    static let seamlessGap: CGFloat = 1

    /// From the bottom of one page's body to the top of the next.
    var gap: CGFloat {
        switch mode {
        case .print:      Self.margin * 2 + Self.printSheetGap
        case .compressed: Self.compressedGap
        case .seamless:   Self.seamlessGap
        }
    }

    /// From the top of one page's body to the top of the next.
    var pitch: CGFloat { bodyHeight + gap }

    /// Where page 0's body begins in the note.
    ///
    /// Print layout shows the first sheet's whole top margin. The continuous
    /// modes show half of it: there is no sheet edge for it to set apart.
    var firstBodyTop: CGFloat {
        mode == .print ? Self.printSheetGap + Self.margin : Self.margin / 2
    }

    /// Space after the last page's body.
    var trailingSpace: CGFloat {
        mode == .print ? Self.margin + Self.printSheetGap : Self.margin
    }

    // MARK: Pages

    func bodyTop(ofPage index: Int) -> CGFloat {
        firstBodyTop + CGFloat(index) * pitch
    }

    /// The page a point in the note belongs to. The boundary is the middle of
    /// the band between two bodies, so ink in a gap goes to the nearer page.
    func pageIndex(atY y: CGFloat) -> Int {
        max(Int(((y - firstBodyTop + gap / 2) / pitch).rounded(.down)), 0)
    }

    /// How many pages a note needs to hold its text and its ink. At least one.
    ///
    /// - Parameters:
    ///   - textBottom: the bottom of the last line, in note coordinates.
    ///   - inkBottom: the lowest point of any ink, or `nil` for none.
    func pageCount(textBottom: CGFloat, inkBottom: CGFloat?) -> Int {
        let lowest = max(textBottom, inkBottom ?? 0)
        return pageIndex(atY: lowest) + 1
    }

    /// How tall a note of `pageCount` pages is.
    func noteHeight(pageCount: Int) -> CGFloat {
        bodyTop(ofPage: max(pageCount, 1) - 1) + bodyHeight + trailingSpace
    }

    /// Sheet `index` in print layout, margins included — exactly what would
    /// go to the printer for that page.
    func sheet(ofPage index: Int) -> CGRect {
        CGRect(
            x: 0,
            y: bodyTop(ofPage: index) - Self.margin,
            width: pageSize.width,
            height: pageSize.height
        )
    }

    /// Where compressed layout draws the break after page `index`.
    func breakLineY(afterPage index: Int) -> CGFloat {
        bodyTop(ofPage: index) + bodyHeight + gap / 2
    }

    /// The bands text flows around, one after each of the first `pageCount`
    /// pages, in the text container's coordinates.
    ///
    /// - Parameter containerTop: the note coordinate the container starts at,
    ///   which is the text view's top inset. It must be `firstBodyTop`.
    func exclusionBands(pageCount: Int, containerTop: CGFloat) -> [CGRect] {
        (0..<max(pageCount, 0)).map { index in
            CGRect(
                x: 0,
                y: bodyTop(ofPage: index) + bodyHeight - containerTop,
                width: textWidth,
                height: gap
            )
        }
    }

    // MARK: Between modes

    /// The same point on the same page, in another layout.
    ///
    /// Ink drawn in one mode lands on the same words in any other: the page it
    /// is on doesn't change, and nor does its distance from that page's body.
    /// Horizontal positions don't change between modes at all.
    ///
    /// Exact into print layout and back, from any mode, because print layout's
    /// breaks are the widest. Not exact the other way: a point in a sheet's
    /// margin keeps its distance from the page's body, and in a mode with a
    /// narrower break that distance can reach onto the next page. That is why
    /// `PageView` keeps ink in print layout's coordinates and only ever
    /// converts outward from them.
    ///
    /// Only meaningful between layouts of one orientation. A different
    /// orientation wraps text at a different width, so no position carries
    /// over, and this returns `nil`.
    func convert(y: CGFloat, to other: PageLayout) -> CGFloat? {
        guard other.orientation == orientation else { return nil }
        let index = pageIndex(atY: y)
        return other.bodyTop(ofPage: index) + (y - bodyTop(ofPage: index))
    }

    /// Where to scroll to show page `index` from its top edge.
    ///
    /// The note's very top for the first page. After that: the sheet with a
    /// little of the gap above it in print layout, the dashed line in
    /// compressed, and the break in seamless — so the page's first line isn't
    /// jammed against the top of the view.
    func scrollTop(forPage index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        return mode == .print
            ? sheet(ofPage: index).minY - Self.printSheetGap / 2
            : bodyTop(ofPage: index) - gap / 2
    }
}
