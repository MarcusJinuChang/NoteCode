//
//  PaperTests.swift
//  NoteCodeTests
//
//  Paper styles: the model, how it is stored and the pattern's geometry.
//  The layers, the PDF and the menus have their own suites below.
//

import CoreGraphics
import SwiftData
import Testing
import Foundation

@testable import NoteCode

@Suite("Paper: the model and its geometry")
@MainActor
struct PaperTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private static let everySetup: [PaperSetup] = PaperStyle.allCases.flatMap { style in
        PaperSpacing.allCases.flatMap { spacing in
            PaperStrength.allCases.map { PaperSetup(style: style, spacing: spacing, strength: $0) }
        }
    }

    // MARK: Stored form

    @Test("Blank is nothing stored, whatever else was chosen")
    func blankIsNil() {
        #expect(PaperSetup.blank.stored == nil)
        #expect(PaperSetup(style: .blank, spacing: .wide, strength: .strong).stored == nil)
        #expect(PaperSetup(stored: nil) == .blank)
    }

    @Test("Trailing defaults are left out")
    func storedForms() {
        #expect(PaperSetup(style: .grid).stored == "grid")
        #expect(PaperSetup(style: .grid, spacing: .fine).stored == "grid/fine")
        #expect(PaperSetup(style: .lined, strength: .strong).stored == "lined/standard/strong")
        #expect(PaperSetup(style: .dots, spacing: .wide, strength: .light).stored == "dots/wide/light")
    }

    @Test("Every setup reads back as it was written")
    func roundTrip() {
        for setup in Self.everySetup where !setup.isBlank {
            #expect(PaperSetup(stored: setup.stored) == setup, "\(setup)")
        }
    }

    @Test("Values a later build might write never break this one")
    func unknownValues() {
        #expect(PaperSetup(stored: "hexagons") == .blank)
        #expect(PaperSetup(stored: "") == .blank)
        #expect(PaperSetup(stored: "grid/huge/loud") == PaperSetup(style: .grid))
        #expect(PaperSetup(stored: "dots/fine/extra/more") == PaperSetup(style: .dots, spacing: .fine))
    }

    // MARK: The note

    @Test("A note's paper is its stored string, and setting it is not an edit")
    func noteRoundTrip() {
        let page = Page(title: "x")
        let modified = page.modifiedAt
        #expect(page.paper == .blank)
        PaperSetup(style: .grid, spacing: .fine).apply(to: page)
        #expect(page.paperStyle == "grid/fine")
        #expect(page.paper == PaperSetup(style: .grid, spacing: .fine))
        #expect(page.modifiedAt == modified)
        PaperSetup.blank.apply(to: page)
        #expect(page.paperStyle == nil)
    }

    @Test("Duplicate copies the paper")
    func duplicateCopies() {
        let page = Page(title: "x")
        context.insert(page)
        PaperSetup(style: .lined, spacing: .wide, strength: .light).apply(to: page)
        let copy = page.duplicated(in: context)
        #expect(copy.paper == page.paper)
    }

    @Test("A new note takes the device's default; the default changes new notes only")
    func newNotesTakeTheDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "PaperTests-\(UUID().uuidString)"))
        #expect(PaperSetup.preferred(in: defaults) == .blank)

        defaults.set("grid", forKey: PaperSetup.defaultStyleKey)
        defaults.set("fine", forKey: PaperSetup.defaultSpacingKey)
        defaults.set("loud", forKey: PaperSetup.defaultStrengthKey)
        let preferred = PaperSetup.preferred(in: defaults)
        #expect(preferred == PaperSetup(style: .grid, spacing: .fine, strength: .default), "an unknown strength is the default")

        let before = Page.create(orientation: .portrait, paper: .blank, context: context)
        let after = Page.create(orientation: .portrait, paper: preferred, context: context)
        #expect(before.paper == .blank)
        #expect(after.paper == preferred)

        let template = Page.create(from: .lecture, orientation: .portrait, paper: preferred, context: context)
        #expect(template.paper == preferred, "templates go through Page.create")
    }

    @Test("The default is written as one value and read back as it was")
    func defaultRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "PaperTests-\(UUID().uuidString)"))
        for setup in Self.everySetup {
            setup.apply(to: defaults)
            #expect(PaperSetup.preferred(in: defaults) == setup)
        }
    }

    // MARK: Geometry

    @Test("Rules and dots fall on multiples of the spacing, none on the edge")
    func offsets() {
        for spacing in PaperSpacing.allCases {
            let setup = PaperSetup(style: .grid, spacing: spacing)
            for extent in [CGFloat(816), 960, 1056] {
                let offsets = setup.offsets(along: extent)
                #expect(offsets.first == spacing.points)
                #expect(offsets.allSatisfy { $0 > 0 && $0 < extent })
                #expect(offsets.enumerated().allSatisfy { $0.element == CGFloat($0.offset + 1) * spacing.points })
                // The next one would be on or past the edge.
                #expect((offsets.last ?? 0) + spacing.points >= extent - 0.5)
            }
        }
        // A quarter inch across a Letter page's width and a body's height.
        let standard = PaperSetup(style: .grid)
        #expect(standard.offsets(along: 816).count == 33)
        #expect(standard.offsets(along: 960).count == 39)
    }

    @Test("Each style draws its own shapes")
    func shapesByStyle() {
        let size = CGSize(width: 816, height: 960)
        let blank = PaperSetup(style: .blank).shapes(in: size)
        #expect(blank.rules.isEmpty && blank.dots.isEmpty)

        let lined = PaperSetup(style: .lined).shapes(in: size)
        #expect(lined.rules.count == 39 && lined.dots.isEmpty)
        #expect(lined.rules.allSatisfy { $0.width == size.width && $0.height == PaperSetup.lineWidth })

        let grid = PaperSetup(style: .grid).shapes(in: size)
        #expect(grid.rules.count == 39 + 33 && grid.dots.isEmpty)
        #expect(grid.rules.allSatisfy { CGRect(origin: .zero, size: size).contains($0) })

        let dots = PaperSetup(style: .dots).shapes(in: size)
        #expect(dots.rules.isEmpty && dots.dots.count == 39 * 33)
        #expect(dots.dots.allSatisfy { $0.x.truncatingRemainder(dividingBy: 24) == 0 && $0.y.truncatingRemainder(dividingBy: 24) == 0 })
    }

    @Test("The stroked path covers the same lines as the filled shapes")
    func strokeMatchesShapes() {
        let size = CGSize(width: 816, height: 960)
        for style in [PaperStyle.lined, .grid, .dots] {
            let setup = PaperSetup(style: style, spacing: .fine)
            let path = setup.strokePath(in: size)
            #expect(!path.isEmpty)
            #expect(path.boundingBoxOfPath.minX >= 0 && path.boundingBoxOfPath.maxY <= size.height, "\(style)")
        }
        #expect(PaperSetup(style: .blank).strokePath(in: size).isEmpty)
        #expect(PaperSetup(style: .dots).dash == [0, 24])
        #expect(PaperSetup(style: .grid).dash == nil)
        #expect(PaperSetup(style: .dots).strokeWidth == PaperSetup.dotDiameter)
    }

    // MARK: Colour

    @Test("Blank has no tone; stronger is more opaque; dots are stronger than rules")
    func tones() {
        for dark in [false, true] {
            #expect(PaperSetup(style: .blank).tone(dark: dark) == nil)
            for style in [PaperStyle.dots, .grid, .lined] {
                let alphas = PaperStrength.allCases.map { PaperSetup(style: style, strength: $0).tone(dark: dark)!.alpha }
                #expect(alphas == alphas.sorted() && Set(alphas).count == 3, "\(style) dark=\(dark)")
            }
            #expect(PaperSetup(style: .dots).tone(dark: dark)!.alpha > PaperSetup(style: .grid).tone(dark: dark)!.alpha)
            #expect(PaperSetup(style: .grid).tone(dark: dark)!.alpha == PaperSetup(style: .lined).tone(dark: dark)!.alpha)
        }
    }

    /// WCAG relative luminance of an sRGB colour.
    private static func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
        func channel(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    @Test("The label stays 4.5:1 on the page under the strongest paper")
    func textStaysLegible() {
        for dark in [false, true] {
            let page: CGFloat = dark ? 0 : 1
            let label: CGFloat = dark ? 1 : 0
            for setup in Self.everySetup where !setup.isBlank {
                let tone = setup.tone(dark: dark)!
                func over(_ c: CGFloat) -> CGFloat { c * tone.alpha + page * (1 - tone.alpha) }
                let ground = Self.luminance(over(tone.red), over(tone.green), over(tone.blue))
                let text = Self.luminance(label, label, label)
                let ratio = (max(ground, text) + 0.05) / (min(ground, text) + 0.05)
                #expect(ratio >= 4.5, "\(setup) dark=\(dark): \(ratio)")
            }
        }
    }

    @Test("The pattern shows against the page")
    func patternShows() {
        for dark in [false, true] {
            let page: CGFloat = dark ? 0 : 1
            for setup in Self.everySetup where !setup.isBlank {
                let tone = setup.tone(dark: dark)!
                let shown = tone.red * tone.alpha + page * (1 - tone.alpha)
                #expect(abs(shown - page) > 0.06, "\(setup) dark=\(dark)")
            }
        }
    }

    // MARK: Where

    @Test("Paper sits in every page's body, inside what ink may use, in every mode")
    func regions() {
        for orientation in PageOrientation.allCases {
            for mode in PageViewMode.allCases {
                let layout = PageLayout(orientation: orientation, mode: mode)
                for count in [1, 3, 8] {
                    let regions = layout.paperRegions(pageCount: count)
                    let ink = layout.inkRegions(pageCount: count)
                    #expect(regions.count == count)
                    for (index, region) in regions.enumerated() {
                        #expect(region.minY == layout.bodyTop(ofPage: index))
                        #expect(region.height == layout.bodyHeight)
                        #expect(region.width == layout.pageSize.width)
                        #expect(ink[index].contains(region), "\(orientation) \(mode) page \(index)")
                    }
                }
            }
        }
    }
}
