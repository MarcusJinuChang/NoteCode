//
//  Paper.swift
//  NoteCode
//
//  What a page is ruled with: nothing, dots, a grid or lines. Pure: the
//  choices, how they are stored, and the positions of every rule and dot.
//  The layers that draw them are in PageView.swift, the PDF's in NotePDF.swift.
//  See docs/design/paper-styles.md.
//

import CoreGraphics
import Foundation

/// The pattern drawn on a note's pages.
nonisolated enum PaperStyle: String, CaseIterable, Sendable {
    case blank
    case dots
    case grid
    case lined

    var title: String {
        switch self {
        case .blank: "Blank"
        case .dots:  "Dots"
        case .grid:  "Grid"
        case .lined: "Lined"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: "rectangle"
        case .dots:  "circle.grid.3x3"
        case .grid:  "grid"
        case .lined: "text.justify"
        }
    }
}

/// Between one rule or dot and the next, in page points.
nonisolated enum PaperSpacing: String, CaseIterable, Sendable {
    case fine
    case standard
    case wide

    static let `default` = PaperSpacing.standard

    /// A quarter inch is standard. Each divides a page's body (960pt).
    var points: CGFloat {
        switch self {
        case .fine:     16
        case .standard: PageLayout.unitsPerInch / 4
        case .wide:     32
        }
    }

    var title: String {
        switch self {
        case .fine:     "Fine"
        case .standard: "Standard"
        case .wide:     "Wide"
        }
    }
}

/// How strongly the pattern shows: its opacity over the page.
nonisolated enum PaperStrength: String, CaseIterable, Sendable {
    case light
    case standard
    case strong

    static let `default` = PaperStrength.standard

    var title: String {
        switch self {
        case .light:    "Light"
        case .standard: "Standard"
        case .strong:   "Strong"
        }
    }
}

/// A colour with an alpha, laid over whatever the page is.
nonisolated struct PaperTone: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func scaled(alphaBy factor: CGFloat) -> PaperTone {
        PaperTone(red: red, green: green, blue: blue, alpha: alpha * factor)
    }
}

/// A note's paper: the pattern, how far apart it is, and how strong.
///
/// Stored as one string in `Page.paperStyle` (`stored`), so adding a part is
/// no model change. **Drawing only**: paper takes no room and no line is placed
/// against it, so changing it moves nothing and is not an edit.
nonisolated struct PaperSetup: Equatable, Sendable {
    var style: PaperStyle = .blank
    var spacing: PaperSpacing = .default
    var strength: PaperStrength = .default

    static let blank = PaperSetup()

    var isBlank: Bool { style == .blank }

    // MARK: Stored form

    /// `nil` for blank, else `style`, `style/spacing` or
    /// `style/spacing/strength`, trailing defaults left out.
    var stored: String? {
        guard !isBlank else { return nil }
        var parts = [style.rawValue]
        if strength != .default {
            parts += [spacing.rawValue, strength.rawValue]
        } else if spacing != .default {
            parts.append(spacing.rawValue)
        }
        return parts.joined(separator: "/")
    }

    /// Reads a stored string. An unknown style is blank, an unknown spacing or
    /// strength the default, so a value a later build wrote never breaks this.
    init(stored: String?) {
        guard let stored else { return }
        let parts = stored.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let style = parts.first.flatMap(PaperStyle.init(rawValue:)) else { return }
        self.style = style
        if parts.count > 1 { spacing = PaperSpacing(rawValue: parts[1]) ?? .default }
        if parts.count > 2 { strength = PaperStrength(rawValue: parts[2]) ?? .default }
    }

    init(style: PaperStyle = .blank, spacing: PaperSpacing = .default, strength: PaperStrength = .default) {
        self.style = style
        self.spacing = spacing
        self.strength = strength
    }

    // MARK: The device's default for new notes

    static let defaultStyleKey = "defaultPaper"
    static let defaultSpacingKey = "defaultPaperSpacing"
    static let defaultStrengthKey = "defaultPaperStrength"

    /// The paper new notes are made with on this device (Settings › Notes).
    static func preferred(in defaults: UserDefaults = .standard) -> PaperSetup {
        PaperSetup(
            style: defaults.string(forKey: defaultStyleKey).flatMap(PaperStyle.init(rawValue:)) ?? .blank,
            spacing: defaults.string(forKey: defaultSpacingKey).flatMap(PaperSpacing.init(rawValue:)) ?? .default,
            strength: defaults.string(forKey: defaultStrengthKey).flatMap(PaperStrength.init(rawValue:)) ?? .default
        )
    }

    // MARK: Colour

    /// The pattern's colour over the page in this appearance, `nil` for blank.
    /// Light is slate, dark is white; both are an alpha over the page, so the
    /// paper matches whatever the page is. Dots are stronger than rules at
    /// the same strength, since a 2pt dot looks fainter than a 1pt line; in
    /// dark they stop short of what would take the label under 4.5:1
    /// (`PaperTests.textStaysLegible`).
    func tone(dark: Bool) -> PaperTone? {
        guard !isBlank else { return nil }
        let level = switch strength {
        case .light:    0
        case .standard: 1
        case .strong:   2
        }
        let alphas: [CGFloat] = switch (style == .dots, dark) {
        case (false, false): [0.12, 0.18, 0.28]
        case (false, true):  [0.08, 0.12, 0.20]
        case (true, false):  [0.30, 0.42, 0.60]
        case (true, true):   [0.20, 0.28, 0.40]
        }
        return dark
            ? PaperTone(red: 1, green: 1, blue: 1, alpha: alphas[level])
            : PaperTone(red: 0x64 / 255, green: 0x74 / 255, blue: 0x8B / 255, alpha: alphas[level])
    }

    /// A printed sheet shows the pattern at this share of the screen's alpha.
    static let printAlphaShare: CGFloat = 0.75

    // MARK: Geometry

    /// A rule's width, and a dot's diameter, in page points.
    static let lineWidth: CGFloat = 1
    static let dotDiameter: CGFloat = 2

    /// Where the rules (or the rows and columns of dots) fall along `extent`,
    /// measured from the body's edge: every multiple of the spacing strictly
    /// inside it. None on the edge itself, which would hang half outside the
    /// layer.
    func offsets(along extent: CGFloat) -> [CGFloat] {
        let step = spacing.points
        var result: [CGFloat] = []
        var offset = step
        while offset < extent - 0.5 {
            result.append(offset)
            offset += step
        }
        return result
    }

    /// The pattern over a body `size` in size: filled rules, and dot centres.
    /// What the PDF draws, and what the tests read.
    func shapes(in size: CGSize) -> PaperShapes {
        let columns = offsets(along: size.width)
        let rows = offsets(along: size.height)
        switch style {
        case .blank:
            return PaperShapes(rules: [], dots: [])
        case .lined:
            return PaperShapes(rules: rows.map { horizontalRule(at: $0, width: size.width) }, dots: [])
        case .grid:
            let horizontal = rows.map { horizontalRule(at: $0, width: size.width) }
            let vertical = columns.map { x in
                CGRect(x: x - Self.lineWidth / 2, y: 0, width: Self.lineWidth, height: size.height)
            }
            return PaperShapes(rules: vertical + horizontal, dots: [])
        case .dots:
            return PaperShapes(rules: [], dots: rows.flatMap { y in columns.map { CGPoint(x: $0, y: y) } })
        }
    }

    private func horizontalRule(at y: CGFloat, width: CGFloat) -> CGRect {
        CGRect(x: 0, y: y - Self.lineWidth / 2, width: width, height: Self.lineWidth)
    }

    /// The same pattern as one stroked path, for a shape layer: strokes need
    /// no backing store, so a layer is as sharp at 4x as at 1x. Rules are
    /// lines; dots are lines stroked with a round cap and the dash
    /// `[0, spacing]`, each zero-length dash being a dot (`dash`).
    func strokePath(in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        let columns = offsets(along: size.width)
        let rows = offsets(along: size.height)
        switch style {
        case .blank:
            break
        case .lined, .grid:
            for y in rows {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            if style == .grid {
                for x in columns {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
        case .dots:
            guard let first = columns.first, let last = columns.last else { break }
            // To half a step past the last dot, so its zero-length dash is
            // inside the line rather than on its end.
            let end = last + spacing.points / 2
            for y in rows {
                path.move(to: CGPoint(x: first, y: y))
                path.addLine(to: CGPoint(x: end, y: y))
            }
        }
        return path
    }

    /// The stroke's line width: a rule's, or a dot's diameter.
    var strokeWidth: CGFloat { style == .dots ? Self.dotDiameter : Self.lineWidth }

    /// `[0, spacing]` for dots, else none.
    var dash: [CGFloat]? { style == .dots ? [0, spacing.points] : nil }
}

/// Filled rectangles for rules and the centres of dots: the pattern as a
/// list, for the PDF and for tests.
nonisolated struct PaperShapes: Equatable, Sendable {
    var rules: [CGRect]
    var dots: [CGPoint]
}

extension PageLayout {

    /// Where paper is drawn: each page's body, the page's full width.
    ///
    /// Inside the page's `inkRegion` in every mode, so none of it falls in a
    /// band the covers hide (print layout's margins and gaps, compressed's
    /// strip), and the margins above and below a body stay plain. The pattern
    /// starts at each region's top left, which is the body's.
    func paperRegions(pageCount: Int) -> [CGRect] {
        (0..<max(pageCount, 1)).map { index in
            CGRect(x: 0, y: bodyTop(ofPage: index), width: pageSize.width, height: bodyHeight)
        }
    }
}

extension Page {

    /// The paper the note is on.
    var paper: PaperSetup {
        get { PaperSetup(stored: paperStyle) }
        set { paperStyle = newValue.stored }
    }
}

extension PaperSetup {

    /// Gives a note this paper. Not an edit: `modifiedAt` is left alone.
    func apply(to page: Page) {
        page.paper = self
    }
}
