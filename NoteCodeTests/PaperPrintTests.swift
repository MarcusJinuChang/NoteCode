//
//  PaperPrintTests.swift
//  NoteCodeTests
//
//  Paper in the PDF and in thumbnails: vector in the file, at the page's
//  positions, light, and fainter than the screen.
//

#if canImport(UIKit)

import CoreGraphics
import Testing
import UIKit

@testable import NoteCode

@Suite("Paper: the PDF and thumbnails")
@MainActor
struct PaperPrintTests {

    /// The PDF's first page drawn into an 8-bit grey bitmap at 1 pixel to the
    /// PDF point, top row first.
    private static func raster(of pdf: Data) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let provider = try #require(CGDataProvider(data: pdf as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width), height = Int(box.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.drawPDFPage(page)
        return (pixels, width, height)
    }

    private static func pdf(paper: PaperSetup) async -> Data {
        await NotePDF.render(NotePDF.Note(title: "t", text: "x", ink: nil, orientation: .portrait, paper: paper))
    }

    /// The darkest pixel in a box `radius` around a PDF point given in page
    /// points from the sheet's top left.
    private static func darkest(_ image: (pixels: [UInt8], width: Int, height: Int), nearPagePoint point: CGPoint, radius: Int = 2) -> UInt8 {
        let scale = NotePDF.pointsPerPagePoint
        let cx = Int((point.x * scale).rounded()), cy = Int((point.y * scale).rounded())
        var darkest: UInt8 = 255
        for y in max(cy - radius, 0)...min(cy + radius, image.height - 1) {
            for x in max(cx - radius, 0)...min(cx + radius, image.width - 1) {
                darkest = min(darkest, image.pixels[y * image.width + x])
            }
        }
        return darkest
    }

    @Test("A printed sheet has the rules at the page's own points, and is bare between them and in the margins")
    func printedGrid() async throws {
        let blank = try Self.raster(of: await Self.pdf(paper: .blank))
        let grid = try Self.raster(of: await Self.pdf(paper: PaperSetup(style: .grid)))

        // A sheet's body starts one margin down; rules are every 24 from there.
        let rule = CGPoint(x: 300, y: PageLayout.margin + 24 * 15)
        #expect(Self.darkest(blank, nearPagePoint: rule) == 255)
        let onRule = Self.darkest(grid, nearPagePoint: rule, radius: 1)
        #expect(onRule < 252, "a horizontal rule: \(onRule)")
        // Not as dark as the screen: printed at three quarters.
        let tone = PaperSetup(style: .grid).tone(dark: false)!
        let screenGrey = 255 * (1 - tone.alpha) + 255 * 0.39 * tone.alpha
        #expect(Double(onRule) > screenGrey - 1, "fainter than the screen's \(screenGrey): \(onRule)")

        let vertical = CGPoint(x: 24 * 17, y: PageLayout.margin + 24 * 15 + 12)
        #expect(Self.darkest(grid, nearPagePoint: vertical, radius: 1) < 252, "a vertical rule")

        let between = CGPoint(x: 24 * 17 + 12, y: PageLayout.margin + 24 * 15 + 12)
        #expect(Self.darkest(grid, nearPagePoint: between, radius: 1) == 255, "the middle of a square")

        // The top margin is not paper: where the lattice would put a rule.
        let margin = CGPoint(x: 300, y: PageLayout.margin - 24)
        #expect(Self.darkest(grid, nearPagePoint: margin, radius: 1) == 255, "the margin above the body")
    }

    @Test("Dots are printed as dots and lined paper as horizontal rules only")
    func printedDotsAndLines() async throws {
        let dots = try Self.raster(of: await Self.pdf(paper: PaperSetup(style: .dots)))
        let lined = try Self.raster(of: await Self.pdf(paper: PaperSetup(style: .lined)))
        let dot = CGPoint(x: 24 * 17, y: PageLayout.margin + 24 * 15)
        #expect(Self.darkest(dots, nearPagePoint: dot, radius: 1) < 252, "a dot")
        #expect(Self.darkest(dots, nearPagePoint: CGPoint(x: dot.x + 12, y: dot.y), radius: 1) == 255, "between dots")
        #expect(Self.darkest(lined, nearPagePoint: dot, radius: 1) < 252, "a line")
        #expect(Self.darkest(lined, nearPagePoint: CGPoint(x: dot.x, y: dot.y + 12), radius: 1) == 255)
        #expect(Self.darkest(lined, nearPagePoint: CGPoint(x: dot.x + 24 * 3, y: dot.y + 12 + 5), radius: 0) == 255, "no vertical rules")
    }

    @Test("A printed note stays vector: paper is drawn, not pictured")
    func vectorFile() async throws {
        let blank = await Self.pdf(paper: .blank)
        let grid = await Self.pdf(paper: PaperSetup(style: .grid, spacing: .fine))
        // A bitmap of the page would be hundreds of kilobytes.
        #expect(grid.count < blank.count + 40_000, "\(grid.count) against \(blank.count)")
    }

    @Test("A thumbnail shows the paper, and blank paper leaves it as it was")
    func thumbnail() async throws {
        func png(_ paper: PaperSetup) async throws -> Data {
            let image = try #require(await NoteThumbnail.render(NoteThumbnail.Source(
                text: "x", orientation: .portrait, drawingData: Data(), paper: paper
            )))
            return try #require(image.pngData())
        }
        let plain = try await png(.blank)
        #expect(try await png(.blank) == plain)
        #expect(try await png(PaperSetup(style: .grid)) != plain)
        #expect(try await png(PaperSetup(style: .dots)) != plain)
        #expect(NoteThumbnail.version >= 7)
    }
}

#endif
