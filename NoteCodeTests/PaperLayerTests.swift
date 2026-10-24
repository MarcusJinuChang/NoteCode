//
//  PaperLayerTests.swift
//  NoteCodeTests
//
//  Paper on the page: where its layers are, that they lay nothing out, and
//  that they sit on the same note points in every mode, appearance and zoom.
//  The old tiled version drifted off its words at some zooms; these read
//  pixels at the rules.
//

#if canImport(UIKit)

import Testing
import UIKit

@testable import NoteCode

@Suite("Paper on the page")
@MainActor
struct PaperLayerTests {

    private final class Harness {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1400, height: 1400))
        let page: PageView

        init(text: String, pages: Int = 3, area: CGSize = CGSize(width: 1300, height: 900), layout: PageLayout = PageLayout()) {
            let textView = DocumentTextView.makeConfiguredTextView()
            textView.text = text
            page = PageView(textView: textView)
            page.pageLayout = layout
            page.minimumPageCount = pages
            page.frame = CGRect(origin: .zero, size: area)
            window.addSubview(page)
            window.makeKeyAndVisible()
            layOut()
        }

        func layOut() {
            for _ in 0..<3 {
                page.setNeedsLayout()
                page.layoutIfNeeded()
                page.textView.setNeedsLayout()
                page.textView.layoutIfNeeded()
            }
        }

        /// Every fragment's frame, laid out to the end, and the content height.
        var shape: [CGRect] {
            guard let manager = page.textView.textLayoutManager,
                  let content = manager.textContentManager else { return [] }
            var frames: [CGRect] = []
            manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) {
                frames.append($0.layoutFragmentFrame)
                return true
            }
            return frames + [CGRect(origin: .zero, size: page.textView.contentSize)]
        }
    }

    private static let prose = (0..<150)
        .map { "Line \($0): the loop invariant holds before and after every iteration." }
        .joined(separator: "\n")

    // MARK: Where

    @Test("A layer to a page body, at the paper regions, and none for blank")
    func layersFollowBodies() {
        for mode in PageViewMode.allCases {
            for orientation in PageOrientation.allCases {
                let layout = PageLayout(orientation: orientation, mode: mode)
                let harness = Harness(text: "x", pages: 4, layout: layout)
                let decorations = harness.page.decorations
                #expect(decorations.paperFrames.isEmpty)

                harness.page.paper = PaperSetup(style: .grid)
                harness.layOut()
                #expect(decorations.paperFrames == layout.paperRegions(pageCount: harness.page.pageCount), "\(mode) \(orientation)")
                #expect(decorations.paperFrames.count == 4)

                harness.page.paper = .blank
                harness.layOut()
                #expect(decorations.paperFrames.isEmpty)
            }
        }
    }

    @Test("Paper is above the sheets after a switch to print layout")
    func aboveSheets() throws {
        let harness = Harness(text: "x", layout: PageLayout(mode: .seamless))
        harness.page.paper = PaperSetup(style: .lined)
        harness.page.pageLayout = PageLayout(mode: .print)
        harness.layOut()
        let decorations = harness.page.decorations
        #expect(!decorations.sheetFrames.isEmpty)
        let host = try #require(decorations.paperShapeLayers.first?.superlayer)
        #expect(decorations.layer.sublayers?.last === host, "the paper's host is the topmost sublayer")
        #expect(host.superlayer === decorations.layer)
    }

    @Test("Paper takes no room: the same lines in the same places, with it and without")
    func laysNothingOut() {
        for mode in PageViewMode.allCases {
            for orientation in PageOrientation.allCases {
                let layout = PageLayout(orientation: orientation, mode: mode)
                let plain = Harness(text: Self.prose, layout: layout)
                let ruled = Harness(text: Self.prose, layout: layout)
                ruled.page.paper = PaperSetup(style: .grid, spacing: .fine, strength: .strong)
                ruled.layOut()
                #expect(ruled.shape == plain.shape, "\(mode) \(orientation)")
                #expect(ruled.page.pageCount == plain.page.pageCount)
                ruled.page.paper = PaperSetup(style: .dots)
                ruled.layOut()
                #expect(ruled.shape == plain.shape, "dots \(mode) \(orientation)")
            }
        }
    }

    // MARK: Pixels

    private static func pixel(of view: UIView, at point: CGPoint) throws -> [Int] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var drawn = false
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            drawn = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        try #require(drawn)
        let cg = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cg, in: CGRect(x: -point.x.rounded(.down), y: -(CGFloat(cg.height) - point.y.rounded(.down) - 1), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return bytes.prefix(3).map(Int.init)
    }

    private static func background(_ style: UIUserInterfaceStyle, _ color: UIColor = .systemBackground) -> [Int] {
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b].map { Int(($0 * 255).rounded()) }
    }

    /// How far a pixel is from the page colour, summed over the channels.
    private static func difference(_ pixel: [Int], _ page: [Int]) -> Int {
        zip(pixel, page).reduce(0) { $0 + abs($1.0 - $1.1) }
    }

    /// Scrolls so the note point `target` is on screen, zoomed to `zoom`
    /// about where it is, and returns where it is in the page view.
    private func bring(_ target: CGPoint, intoViewIn harness: Harness, zoom: CGFloat) -> CGPoint {
        let page = harness.page
        page.textView.contentOffset.y = max(target.y - 300, 0)
        harness.layOut()
        if zoom != 1 {
            page.setZoom(zoom, about: page.textView.convert(target, to: page))
            harness.layOut()
        }
        return page.textView.convert(target, to: page)
    }

    @Test(
        "A rule is on its note point, and the page between rules is bare, in every mode, appearance and zoom",
        arguments: PageViewMode.allCases, [UIUserInterfaceStyle.light, .dark]
    )
    func rulesSitOnTheirPoints(mode: PageViewMode, style: UIUserInterfaceStyle) throws {
        let layout = PageLayout(mode: mode)
        let harness = Harness(text: "x", layout: layout)
        harness.page.overrideUserInterfaceStyle = style
        harness.page.paper = PaperSetup(style: .grid)
        harness.layOut()

        for zoom in [CGFloat(1), 1.37, 1.7, 2.2] {
            // The second page, in the middle of its body, clear of the text.
            let bodyTop = layout.bodyTop(ofPage: 1)
            let onRule = CGPoint(x: 408, y: bodyTop + 24 * 15)
            let betweenRules = CGPoint(x: 408 + 12, y: bodyTop + 24 * 15 + 12)
            let onScreen = bring(onRule, intoViewIn: harness, zoom: zoom)
            try #require(harness.page.bounds.contains(onScreen))
            let between = harness.page.textView.convert(betweenRules, to: harness.page)
            try #require(harness.page.bounds.contains(between))

            let page = Self.background(style)
            // The control: the same two points with no paper, so a snapshot
            // that can't draw at this zoom is told from paper not drawn.
            harness.page.paper = .blank
            harness.layOut()
            let controlA = try Self.pixel(of: harness.page, at: onScreen)
            let controlB = try Self.pixel(of: harness.page, at: between)
            harness.page.paper = PaperSetup(style: .grid)
            harness.layOut()
            #expect(Self.difference(controlA, page) <= 6 && Self.difference(controlB, page) <= 6, "control at zoom \(zoom): \(controlA) \(controlB) against \(page)")
            let ruled = try Self.pixel(of: harness.page, at: onScreen)
            let bare = try Self.pixel(of: harness.page, at: between)
            #expect(Self.difference(ruled, page) >= 15, "zoom \(zoom) on the rule: \(ruled) against \(page)")
            #expect(Self.difference(bare, page) <= 6, "between rules: \(bare) against \(page)")
        }
    }

    @Test("Dots are on the lattice and nowhere between", arguments: [UIUserInterfaceStyle.light, .dark])
    func dotsSitOnTheirPoints(style: UIUserInterfaceStyle) throws {
        let layout = PageLayout(mode: .seamless)
        let harness = Harness(text: "x", layout: layout)
        harness.page.overrideUserInterfaceStyle = style
        harness.page.paper = PaperSetup(style: .dots)
        harness.layOut()

        let bodyTop = layout.bodyTop(ofPage: 1)
        let dot = CGPoint(x: 408, y: bodyTop + 24 * 15)
        let onScreen = bring(dot, intoViewIn: harness, zoom: 1.7)
        let page = Self.background(style)
        #expect(Self.difference(try Self.pixel(of: harness.page, at: onScreen), page) >= 30, "the dot")
        // Half a step along a row and along a column: no dot, no line.
        for offset in [CGPoint(x: 12, y: 0), CGPoint(x: 0, y: 12), CGPoint(x: 12, y: 12)] {
            let point = harness.page.textView.convert(CGPoint(x: dot.x + offset.x, y: dot.y + offset.y), to: harness.page)
            #expect(Self.difference(try Self.pixel(of: harness.page, at: point), page) <= 6, "\(offset)")
        }
    }

    @Test("Print layout's margins and the gap between sheets are as they are with no paper", arguments: [UIUserInterfaceStyle.light, .dark])
    func bandsStayBare(style: UIUserInterfaceStyle) throws {
        let layout = PageLayout(mode: .print)
        let harness = Harness(text: "x", layout: layout)
        harness.page.overrideUserInterfaceStyle = style

        // A rule's place continued up through the sheet's margin and the
        // gap above it: all hidden bands, where nothing may show.
        let bodyTop = layout.bodyTop(ofPage: 1)
        let marginPoint = CGPoint(x: 408, y: bodyTop - 24)
        let gapPoint = CGPoint(x: 408, y: bodyTop - 24 * 4)
        let onScreen = bring(marginPoint, intoViewIn: harness, zoom: 1)
        let gap = harness.page.textView.convert(gapPoint, to: harness.page)
        try #require(harness.page.bounds.contains(gap))

        let without = [try Self.pixel(of: harness.page, at: onScreen), try Self.pixel(of: harness.page, at: gap)]
        harness.page.paper = PaperSetup(style: .grid, strength: .strong)
        harness.layOut()
        let with = [try Self.pixel(of: harness.page, at: onScreen), try Self.pixel(of: harness.page, at: gap)]
        #expect(with == without, "the margin and the gap: \(with) against \(without)")
    }

    // MARK: Cost

    @Test("A long note's paper is cheap to set up and to draw")
    func cost() throws {
        let clock = ContinuousClock()
        let harness = Harness(text: Self.prose, pages: 300)
        let pages = harness.page.pageCount
        try #require(pages == 300)

        var costs: [String] = []
        for style in [PaperStyle.lined, .grid, .dots] {
            let setUp = clock.measure {
                harness.page.paper = PaperSetup(style: style, spacing: .fine)
                harness.page.layoutIfNeeded()
            }
            #expect(setUp < .milliseconds(500), "\(style) on \(pages) pages took \(setUp)")

            // One page body's layer drawn in full, in-process: an upper bound
            // on what the render server does for a page on screen.
            let layer = try #require(harness.page.decorations.paperShapeLayers.first)
            let drawn = clock.measure {
                let renderer = UIGraphicsImageRenderer(size: layer.bounds.size)
                _ = renderer.image { layer.render(in: $0.cgContext) }
            }
            costs.append("\(style): set up \(setUp), one page drawn \(drawn)")
            harness.page.paper = .blank
        }
        print("Paper cost on \(pages) pages: " + costs.joined(separator: "; "))
    }
}

#endif
