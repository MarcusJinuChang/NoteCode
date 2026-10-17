//
//  NotePDFTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PDFKit
import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Note as a PDF")
@MainActor
struct NotePDFTests {

    private static func pdf(
        _ text: String,
        title: String = "Note",
        ink: PaperMarkup? = nil,
        orientation: PageOrientation = .portrait,
        pageCount: Int = 1
    ) async throws -> PDFDocument {
        let data = await NotePDF.render(NotePDF.Note(
            title: title, text: text, ink: ink, orientation: orientation, pageCount: pageCount
        ))
        return try #require(PDFDocument(data: data))
    }

    /// The N of each "Line N:" label in `text`.
    private static func labelledLines(in text: String) -> Set<Int> {
        Set(text.matches(of: /Line (\d+):/).compactMap { Int($0.output.1) })
    }

    // MARK: Pages

    @Test("Each page of the PDF holds the lines print layout puts on that page", arguments: PageOrientation.allCases)
    func linesOnTheirPages(orientation: PageOrientation) async throws {
        let text = PageSettlingTests.note
        let layout = PageLayout(orientation: orientation, mode: .print)

        // The note in print layout on screen, laid out to its end.
        let (window, coordinator, page) = await PageSettlingTests.openNote(text, layout: layout)
        let textView = page.textView
        let manager = try #require(textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        await PageSettlingTests.settle(0.5)
        manager.ensureLayout(for: manager.documentRange)

        var expected: [Int: Int] = [:]
        for match in text.matches(of: /Line (\d+):/) {
            let number = try #require(Int(match.output.1))
            let offset = NSRange(match.range, in: text).location
            let top = try #require(page.lineTop(atCharacter: offset))
            expected[number] = layout.pageIndex(atY: top)
        }

        // Started from one page, so this also checks the page breaks are
        // found without the open note's count.
        let pdf = try await Self.pdf(text, orientation: orientation)
        #expect(pdf.pageCount == page.pageCount, "\(orientation): \(pdf.pageCount) PDF pages for \(page.pageCount) note pages")

        var printed: [Int: Int] = [:]
        var copies: [Int: Int] = [:]
        for index in 0..<pdf.pageCount {
            let pageText = pdf.page(at: index)?.string ?? ""
            for number in Self.labelledLines(in: pageText) {
                printed[number] = index
                copies[number, default: 0] += 1
            }
        }
        #expect(printed == expected, "\(orientation): lines landed on different pages than print layout shows")
        // A paragraph split by a page break is in the PDF once, not once
        // per page it reaches.
        #expect(copies.values.allSatisfy { $0 == 1 }, "\(orientation): lines in the PDF more than once: \(copies.filter { $0.value > 1 })")
        withExtendedLifetime((window, coordinator)) {}
    }

    @Test("A page is US Letter, the way round the note's pages are", arguments: PageOrientation.allCases)
    func letterSize(orientation: PageOrientation) async throws {
        let pdf = try await Self.pdf("One line", orientation: orientation)
        let box = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)

        let expected = orientation == .portrait ? CGSize(width: 612, height: 792) : CGSize(width: 792, height: 612)
        #expect(box.size == expected)
        #expect(pdf.pageCount == 1)
    }

    @Test("A page count from a note that has since got shorter still gives the right pages")
    func staleCount() async throws {
        let text = PageSettlingTests.note
        let fromOne = try await Self.pdf(text)
        let fromTwenty = try await Self.pdf(text, pageCount: 20)
        #expect(fromOne.pageCount > 3)
        #expect(fromTwenty.pageCount == fromOne.pageCount)
    }

    @Test("The PDF carries the note's title")
    func title() async throws {
        let pdf = try await Self.pdf("Body", title: "Lecture 4: Heaps")
        #expect(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Lecture 4: Heaps")
    }

    // MARK: Colours

    @Test("Text and code panels print in their light colours even when the device is dark")
    func lightOnDarkDevice() async throws {
        let printed = await PrintedNote(text: "Prose typed in dark mode\n```cpp\nint x = 1;\n```", orientation: .portrait)
        let count = printed.paginate(inkBottom: nil, startingAt: 1)
        let sheet = printed.layout.sheet(ofPage: 0)
        let paragraphs = printed.paragraphsByPage(pageCount: count)[0]

        // Drawn synchronously, so nothing else runs under the dark trait.
        let saved = UITraitCollection.current
        UITraitCollection.current = UITraitCollection(userInterfaceStyle: .dark)
        let bitmap = Bitmap(size: sheet.size, scale: 1, flipped: true) { context in
            printed.draw(paragraphs, onSheet: sheet, in: context)
        }
        UITraitCollection.current = saved

        // The first line, from the left margin: dark text, not white.
        #expect(bitmap.darkest(in: CGRect(x: 72, y: 72, width: 220, height: 20)) < 0.3)
        // Beside the code line, past its text: the panel's light grey,
        // neither the page's white nor dark mode's panel.
        let panel = bitmap.luminance(at: CGPoint(x: 600, y: 120))
        #expect(panel > 0.85 && panel < 0.99, "panel luminance \(panel)")
    }

    @Test("Code prints in the light theme's colours even when the device is dark")
    func lightSyntaxOnDarkDevice() async throws {
        // A text view in no window takes its appearance from the scene, and
        // an override on the view itself doesn't change it, so the scene is
        // what makes this device dark: whatever the simulator's appearance,
        // and taken off again after.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes { scene.traitOverrides.userInterfaceStyle = .dark }
        defer { for scene in scenes { scene.traitOverrides.remove(UITraitUserInterfaceStyle.self) } }
        try #require(UITextView().traitCollection.userInterfaceStyle == .dark)

        let pdf = try await Self.pdf("```cpp\nint main() {\n    return 0;\n}\n```")
        let page = try #require(Bitmap(pdfPage: pdf.page(at: 0), scale: 4))

        // `return` is a keyword and `int` a type: each is on the page in the
        // light theme's colour, and nowhere in the dark theme's.
        for role in [\SyntaxTheme.keyword, \.type] {
            let light = SyntaxTheme.light[keyPath: role].hex
            let dark = SyntaxTheme.dark[keyPath: role].hex
            let inLight = page.pixelCount(near: light)
            let inDark = page.pixelCount(near: dark)
            #expect(inLight > 20, "\(inLight) pixels in light \(light)")
            #expect(inDark == 0, "\(inDark) pixels in dark \(dark)")
        }
    }

    @Test("A page drawn a line at a time looks the same as TextKit drawing its paragraphs whole")
    func linesMatchFragments() async throws {
        let text = "# Heading\nA paragraph long enough to wrap onto a second line on a portrait page, so one paragraph has two lines.\n```cpp\nint main() {\n    return 0; // gjpqy\n}\n```\nAfter the block."
        let printed = await PrintedNote(text: text, orientation: .portrait)
        let count = printed.paginate(inkBottom: nil, startingAt: 1)
        try #require(count == 1)
        let sheet = printed.layout.sheet(ofPage: 0)
        let paragraphs = printed.paragraphsByPage(pageCount: count)[0]

        let byLine = Bitmap(size: sheet.size, scale: 2, flipped: true) { context in
            printed.draw(paragraphs, onSheet: sheet, in: context)
        }
        // The same page through each fragment's own draw, as the editor's
        // views draw it. One page, so no paragraph is split.
        let inset = printed.textView.textContainerInset
        let whole = Bitmap(size: sheet.size, scale: 2, flipped: true) { context in
            context.translateBy(x: inset.left, y: inset.top - sheet.minY)
            UIGraphicsPushContext(context)
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                for paragraph in paragraphs.reversed() {
                    let origin = paragraph.fragment.layoutFragmentFrame.origin
                    paragraph.fragment.draw(at: origin, in: context)
                    // The language's name, which the screen shows in a button
                    // over the header and paper draws itself.
                    (paragraph.fragment as? CodeBlockLayoutFragment)?.drawHeaderLabel(at: origin, in: context)
                }
            }
            UIGraphicsPopContext()
        }

        #expect(byLine.darkest(in: CGRect(x: 72, y: 72, width: 300, height: 30)) < 0.3)
        #expect(byLine.differingPixels(from: whole) < 20)
    }

    // MARK: Ink

    @Test("Ink prints on its own page, where it was drawn, the right way up")
    func inkOnItsPage() async throws {
        let layout = PageLayout(orientation: .portrait, mode: .print)
        // 300pt down the second sheet, where the note has no text.
        let ink = TestInk.markup(strokesAt: [layout.sheet(ofPage: 1).minY + 300])

        let pdf = try await Self.pdf("One line of text", ink: ink)
        try #require(pdf.pageCount == 2)
        let first = try #require(Bitmap(pdfPage: pdf.page(at: 0)))
        let second = try #require(Bitmap(pdfPage: pdf.page(at: 1)))

        // TestInk's stroke runs from x 100 to 190, in page points.
        let scale = NotePDF.pointsPerPagePoint
        let stroke = CGRect(x: 100 * scale, y: 294 * scale, width: 90 * scale, height: 12 * scale)
        let upsideDown = CGRect(x: stroke.minX, y: 792 - stroke.maxY, width: stroke.width, height: stroke.height)

        #expect(second.darkest(in: stroke) < 0.5)
        #expect(second.darkest(in: upsideDown) > 0.95)
        #expect(first.darkest(in: stroke) > 0.95)
    }

    @Test("A stroke across a page break prints only on the page it was started on")
    func overflowDoesNotPrint() async throws {
        let layout = PageLayout(orientation: .portrait, mode: .print)
        let bottom = layout.bodyTop(ofPage: 0) + layout.bodyHeight
        let top = layout.bodyTop(ofPage: 1)
        // Straight down at x 400, from 40 above page 1's last line to 40
        // below page 2's first, cut as drawing cuts it.
        let points = stride(from: bottom - 40, through: top + 40, by: 4).enumerated().map { index, y in
            PKStrokePoint(location: CGPoint(x: 400, y: y), timeOffset: Double(index) * 0.01, size: CGSize(width: 6, height: 6),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        let pieces = InkPages.pieces(ofStroke: stroke, regions: layout.inkRegions(pageCount: 2))
        try #require(pieces.count == 2)
        var ink = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 100_000))
        for piece in pieces {
            ink.subelements.append(piece)
        }

        let pdf = try await Self.pdf("One line of text", ink: ink)
        try #require(pdf.pageCount == 2)
        let first = try #require(Bitmap(pdfPage: pdf.page(at: 0)))
        let second = try #require(Bitmap(pdfPage: pdf.page(at: 1)))

        // In page points from each sheet's top: 40 points of stroke above
        // the first page's last line, and where the second page's 40 would be.
        let scale = NotePDF.pointsPerPagePoint
        let margin = PageLayout.margin
        let above = CGRect(x: 395 * scale, y: (margin + layout.bodyHeight - 36) * scale, width: 10 * scale, height: 30 * scale)
        let below = CGRect(x: 395 * scale, y: (margin + 6) * scale, width: 10 * scale, height: 30 * scale)
        #expect(first.darkest(in: above) < 0.5)
        #expect(second.darkest(in: below) > 0.95)
    }

    /// Each sheet's ink was added an element at a time, and each add costs
    /// what the markup's `count` does: 7.2s for a note of 2,000 strokes,
    /// against 1.8s now, most of it PaperKit drawing (simulator, 10
    /// October). Loose on purpose: this catches the slow way coming back.
    @Test("A note of 2,000 strokes prints within budget, every stroke on its page")
    func printingCost() async throws {
        let ink = PageViewTests.handwriting(2000)
        let start = Date()
        let pdf = try await Self.pdf("Handwritten", ink: ink)
        let took = Date().timeIntervalSince(start)

        // 930 strokes to a sheet, so the third has the last 140.
        try #require(pdf.pageCount == 3)
        let third = try #require(Bitmap(pdfPage: pdf.page(at: 2)))
        let scale = NotePDF.pointsPerPagePoint
        let firstRow = CGRect(x: 80 * scale, y: (PageLayout.margin + 4) * scale, width: 600 * scale, height: 24 * scale)
        #expect(third.darkest(in: firstRow) < 0.5)
        #expect(took < 4, "printing took \(took)s")
    }

    @Test("Ink goes on the page as a picture at print resolution, and text doesn't")
    func inkResolution() async throws {
        let layout = PageLayout(orientation: .portrait, mode: .print)
        let ink = TestInk.markup(strokesAt: [layout.sheet(ofPage: 1).minY + 300])
        let stroke = try #require(ink.subelements.first).renderFrame

        let pdf = try await Self.pdf("Text on the first page, ink on the second", ink: ink)
        try #require(pdf.pageCount == 2)
        let textPage = try #require(pdf.page(at: 0)?.pageRef)
        let inkPage = try #require(pdf.page(at: 1)?.pageRef)

        #expect(Self.imageWidths(on: textPage).isEmpty)
        // Cropped to the stroke, give or take its edges, at three pixels a
        // page point: 288 dots per inch.
        let widths = Self.imageWidths(on: inkPage)
        try #require(widths.count == 1, "images on the inked page: \(widths)")
        let expected = Int(stroke.width * NotePDF.inkPixelsPerPagePoint)
        #expect(widths[0] >= expected && widths[0] <= expected + 40, "image \(widths[0]) pixels wide for a stroke \(stroke.width) points wide")
    }

    /// The pixel width of each image a PDF page draws, including inside its
    /// form objects.
    private static func imageWidths(on page: CGPDFPage) -> [Int] {
        guard let dictionary = page.dictionary else { return [] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return [] }
        return imageWidths(in: resources)
    }

    private static func imageWidths(in resources: CGPDFDictionaryRef) -> [Int] {
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return [] }

        var streams: [CGPDFStreamRef] = []
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream {
                streams.append(stream)
            }
            return true
        }, nil)

        var widths: [Int] = []
        for stream in streams {
            guard let dictionary = CGPDFStreamGetDictionary(stream) else { continue }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { continue }
            switch String(cString: subtype) {
            case "Image":
                var width: CGPDFInteger = 0
                _ = CGPDFDictionaryGetInteger(dictionary, "Width", &width)
                widths.append(width)
            case "Form":
                var nested: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dictionary, "Resources", &nested), let nested {
                    widths += imageWidths(in: nested)
                }
            default:
                break
            }
        }
        return widths
    }

    // MARK: Files

    @Test("The shared file is named for the note, without characters a file name can't hold")
    func fileName() {
        #expect(NotePDF.fileName(for: "Lecture 4: Heaps/Stacks") == "Lecture 4- Heaps-Stacks.pdf")
        #expect(NotePDF.fileName(for: "  ") == "Untitled.pdf")
        #expect(NotePDF.fileName(for: "Binary search") == "Binary search.pdf")
    }

    @Test("Writing the PDF puts it in a file of that name, replacing an earlier one")
    func write() throws {
        let first = try NotePDF.write(Data("first".utf8), title: "Export test")
        let second = try NotePDF.write(Data("second".utf8), title: "Export test")
        #expect(first == second)
        #expect(first.lastPathComponent == "Export test.pdf")
        #expect(try Data(contentsOf: second) == Data("second".utf8))
        try? FileManager.default.removeItem(at: second)
    }
}

/// Pixels to check a drawing by, in points from the top left.
struct Bitmap {
    let width: Int
    let height: Int
    let scale: CGFloat
    private let pixels: [UInt8]

    /// - Parameter flipped: draws with UIKit's origin at the top left, the
    ///   way the PDF's pages are drawn into. A PDF page itself draws the
    ///   other way up, with its origin at the bottom left.
    init(size: CGSize, scale: CGFloat, flipped: Bool, draw: (CGContext) -> Void) {
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if flipped {
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: scale, y: -scale)
            } else {
                context.scaleBy(x: scale, y: scale)
            }
            draw(context)
        }
        self.width = width
        self.height = height
        self.scale = scale
        self.pixels = pixels
    }

    /// A PDF page at `scale` times its size, white behind it.
    init?(pdfPage page: PDFPage?, scale: CGFloat = 2) {
        guard let ref = page?.pageRef else { return nil }
        self.init(size: ref.getBoxRect(.mediaBox).size, scale: scale, flipped: false) { context in
            context.drawPDFPage(ref)
        }
    }

    /// 0 for black, 1 for white.
    func luminance(at point: CGPoint) -> CGFloat {
        let x = min(max(Int(point.x * scale), 0), width - 1)
        let y = min(max(Int(point.y * scale), 0), height - 1)
        let index = (y * width + x) * 4
        let red = CGFloat(pixels[index]), green = CGFloat(pixels[index + 1]), blue = CGFloat(pixels[index + 2])
        return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
    }

    /// How many pixels differ by more than rounding from another bitmap of
    /// the same size.
    func differingPixels(from other: Bitmap) -> Int {
        guard width == other.width, height == other.height else { return width * height }
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 where abs(Int(pixels[index + channel]) - Int(other.pixels[index + channel])) > 2 {
                count += 1
                break
            }
        }
        return count
    }

    /// How many pixels are a colour, within `tolerance` on each channel: a
    /// glyph's inside, where nothing is blended with what's behind it.
    func pixelCount(near hex: String, tolerance: Int = 8) -> Int {
        guard let value = UInt32(hex, radix: 16) else { return 0 }
        let target = [Int(value >> 16 & 0xFF), Int(value >> 8 & 0xFF), Int(value & 0xFF)]
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4)
        where (0..<3).allSatisfy({ abs(Int(pixels[index + $0]) - target[$0]) <= tolerance }) {
            count += 1
        }
        return count
    }

    /// The darkest pixel in `rect`.
    func darkest(in rect: CGRect) -> CGFloat {
        var darkest: CGFloat = 1
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                darkest = min(darkest, luminance(at: CGPoint(x: x, y: y)))
                x += 1 / scale
            }
            y += 1 / scale
        }
        return darkest
    }
}

#endif
