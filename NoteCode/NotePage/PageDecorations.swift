//
//  PageDecorations.swift
//  NoteCode
//
//  What the page draws behind and over its text and ink: sheets and break
//  lines (`PageDecorationView`), and the covers over ink (`PageCoverView`).
//

#if canImport(UIKit)

import UIKit

// MARK: - Decorations

/// What a view mode draws behind the text: nothing for seamless, a dashed
/// line at each break for compressed, a sheet of paper per page for print.
///
/// One small view or layer per page rather than one tall drawing. A drawn
/// view as tall as a forty-page note would need a backing store to match.
final class PageDecorationView: UIView {

    private var sheets: [UIView] = []
    private var breaks: [CAShapeLayer] = []
    private var layout: PageLayout?
    private var pageCount = 0

    /// Sheet frames in note coordinates, for tests.
    var sheetFrames: [CGRect] { sheets.map(\.frame) }

    /// Each sheet's border width, for tests.
    var sheetBorderWidths: [CGFloat] { sheets.map(\.layer.borderWidth) }

    /// Break line heights in note coordinates, for tests.
    var breakLineYs: [CGFloat] { breaks.map { $0.frame.midY } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PageDecorationView, _) in
            view.resolveColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: PageLayout, pageCount: Int, height: CGFloat) {
        let frame = CGRect(x: 0, y: 0, width: layout.pageSize.width, height: height)
        if self.frame != frame {
            self.frame = frame
        }
        guard layout != self.layout || pageCount != self.pageCount else { return }
        self.layout = layout
        self.pageCount = pageCount

        let sheetCount = layout.mode == .print ? pageCount : 0
        while sheets.count < sheetCount {
            let sheet = Self.makeSheet()
            addSubview(sheet)
            sheets.append(sheet)
        }
        while sheets.count > sheetCount {
            sheets.removeLast().removeFromSuperview()
        }
        for (index, sheet) in sheets.enumerated() {
            Self.place(sheet, at: layout.sheet(ofPage: index))
        }

        let breakCount = layout.mode == .compressed ? max(pageCount - 1, 0) : 0
        while breaks.count < breakCount {
            let line = Self.makeBreakLine()
            layer.addSublayer(line)
            breaks.append(line)
        }
        while breaks.count > breakCount {
            breaks.removeLast().removeFromSuperlayer()
        }
        for (index, line) in breaks.enumerated() {
            Self.place(line, atY: layout.breakLineY(afterPage: index), width: frame.width)
        }

        resolveColors()
    }

    /// CALayer colours are plain CGColors and don't follow dark mode on their
    /// own, so they're re-resolved whenever the appearance changes.
    private func resolveColors() {
        Self.resolveColors(sheets: sheets, lines: breaks, for: traitCollection)
    }

    // MARK: Pieces, shared with the covers

    /// A sheet of paper for print layout.
    static func makeSheet() -> UIView {
        let sheet = UIView()
        sheet.backgroundColor = .systemBackground
        sheet.layer.shadowColor = UIColor.black.cgColor
        sheet.layer.shadowOpacity = 0.12
        sheet.layer.shadowRadius = 6
        sheet.layer.shadowOffset = CGSize(width: 0, height: 2)
        // The page's border, in both appearances. The shadow lifts the
        // sheet off the surround in light mode; dark mode swallows it.
        sheet.layer.borderWidth = 1
        return sheet
    }

    static func place(_ sheet: UIView, at frame: CGRect) {
        sheet.frame = frame
        sheet.layer.shadowPath = UIBezierPath(rect: sheet.bounds).cgPath
    }

    /// Compressed layout's dashed line at a page end.
    static func makeBreakLine() -> CAShapeLayer {
        let line = CAShapeLayer()
        line.lineWidth = 1
        line.lineDashPattern = [6, 5]
        line.fillColor = nil
        return line
    }

    /// Puts a break line across a page `width` wide, centred on `y`.
    static func place(_ line: CAShapeLayer, atY y: CGFloat, width: CGFloat) {
        line.frame = CGRect(x: 0, y: y - 0.5, width: width, height: 1)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: PageLayout.margin / 2, y: 0.5))
        path.addLine(to: CGPoint(x: width - PageLayout.margin / 2, y: 0.5))
        line.path = path.cgPath
    }

    static func resolveColors(sheets: [UIView], lines: [CAShapeLayer], for traits: UITraitCollection) {
        let separator = UIColor.separator.resolvedColor(with: traits).cgColor
        for sheet in sheets {
            sheet.layer.borderColor = separator
        }
        for line in lines {
            line.strokeColor = separator
        }
    }
}

// MARK: - Covers

/// Hides ink where seamless has no room: compressed's strip, and print
/// layout's top and bottom margins and the surround between its sheets
/// (`PageLayout.inkHiddenBands`).
///
/// It sits above the canvas and draws what the page draws there anyway —
/// the page and its dashed line in compressed, the surround and the
/// sheets' edges and shadows in print layout — so on a page without ink
/// it can't be told apart from what's beneath. Text never sits in these
/// bands: they're inside the ones text flows around. A stroke being drawn
/// across one goes under it, and so does a stroke drawn there that the
/// canvas still holds whole until ink is next shown (`InkCapture.State.wholeOnCanvas`).
///
/// It replaced a mask on the canvas (9 October). Masked, the canvas's ink
/// tiles painted the page white over the text beneath them: around every
/// stroke in print layout, whole blocks of lines lost their words
/// (simulator; taking the mask off in the running app brought them back).
/// A view over the ink needs no offscreen pass, either.
final class PageCoverView: UIView {

    private var bands: [UIView] = []
    private var sheets: [UIView] = []
    private var lines: [CAShapeLayer] = []
    private var layout: PageLayout?
    private var pageCount = 0

    /// Each band's frame in note coordinates, for tests.
    var bandFrames: [CGRect] { bands.map(\.frame) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PageCoverView, _) in
            PageDecorationView.resolveColors(sheets: view.sheets, lines: view.lines, for: view.traitCollection)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: PageLayout, pageCount: Int, height: CGFloat) {
        let frame = CGRect(x: 0, y: 0, width: layout.pageSize.width, height: height)
        if self.frame != frame {
            self.frame = frame
        }
        guard layout != self.layout || pageCount != self.pageCount else { return }
        self.layout = layout
        self.pageCount = pageCount

        for band in bands {
            band.removeFromSuperview()
        }
        bands = []
        sheets = []
        lines = []

        for area in layout.inkHiddenBands(pageCount: pageCount) {
            let band = UIView(frame: area)
            band.clipsToBounds = true
            band.isUserInteractionEnabled = false
            band.backgroundColor = layout.mode == .print ? PageView.surroundColor : PageView.pageColor
            switch layout.mode {
            case .print:
                for index in 0..<max(pageCount, 1) where layout.sheet(ofPage: index).intersects(area) {
                    let sheet = PageDecorationView.makeSheet()
                    PageDecorationView.place(sheet, at: layout.sheet(ofPage: index).offsetBy(dx: 0, dy: -area.minY))
                    band.addSubview(sheet)
                    sheets.append(sheet)
                }
            case .compressed:
                for index in 0..<max(pageCount - 1, 0) {
                    let y = layout.breakLineY(afterPage: index)
                    guard y > area.minY, y < area.maxY else { continue }
                    let line = PageDecorationView.makeBreakLine()
                    PageDecorationView.place(line, atY: y - area.minY, width: area.width)
                    band.layer.addSublayer(line)
                    lines.append(line)
                }
            case .seamless:
                break
            }
            addSubview(band)
            bands.append(band)
        }
        PageDecorationView.resolveColors(sheets: sheets, lines: lines, for: traitCollection)
    }
}

#endif
