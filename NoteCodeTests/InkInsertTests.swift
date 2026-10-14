//
//  InkInsertTests.swift
//  NoteCodeTests
//
//  Insert: shapes, a text box and a photo on the page, kept like any ink.
//

#if canImport(UIKit)

import PDFKit
import PaperKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Insert into ink")
@MainActor
struct InkInsertTests {

    // MARK: Where, and how big

    private static let print = PageLayout(orientation: .portrait, mode: .print)

    @Test("Centred in a margin print layout hides, an element goes to the page on screen instead")
    func centreLeavesTheBands() {
        let regions = Self.print.inkRegions(pageCount: 3)
        let gap = (regions[0].maxY + regions[1].minY) / 2
        let visible = CGRect(x: 0, y: gap - 300, width: 816, height: 600)
        try? #require(!Self.print.takesInk(at: CGPoint(x: 408, y: gap), pageCount: 3))

        let extent = InkInsertion.shapeExtent
        let centre = InkInsertion.centre(in: visible, regions: regions, extent: extent)

        #expect(Self.print.takesInk(at: centre, pageCount: 3))
        let element = CGRect(x: centre.x - extent.width / 2, y: centre.y - extent.height / 2, width: extent.width, height: extent.height)
        #expect(regions.contains { $0.contains(element) }, "\(element) isn't on one page of \(regions)")
    }

    @Test("In seamless, the middle of the screen stays the middle")
    func centreKeepsTheMiddle() {
        let layout = PageLayout(orientation: .portrait, mode: .seamless)
        let regions = layout.inkRegions(pageCount: 3)
        let visible = CGRect(x: 0, y: layout.bodyTop(ofPage: 1) + 100, width: 816, height: 600)

        let centre = InkInsertion.centre(in: visible, regions: regions, extent: InkInsertion.shapeExtent)

        #expect(centre.y == visible.midY)
        #expect(centre.x == 408)
    }

    @Test("An element is kept on its page even when the middle of the screen is at the page's edge")
    func centreStaysOffTheBreak() throws {
        let regions = Self.print.inkRegions(pageCount: 3)
        let edge = regions[1].maxY - 10
        let visible = CGRect(x: 0, y: edge - 300, width: 816, height: 600)
        let extent = InkInsertion.shapeExtent

        let centre = InkInsertion.centre(in: visible, regions: regions, extent: extent)

        #expect(centre.y + extent.height / 2 <= regions[1].maxY)
    }

    @Test("A photo is fitted inside a share of the page and never drawn bigger than 2 pixels to the point")
    func photoSize() {
        let big = InkInsertion.photoSize(pixels: CGSize(width: 4000, height: 3000), pageWidth: 816, maxHeight: 500)
        #expect(big.width <= 816 * InkInsertion.photoWidthShare)
        #expect(big.height <= 500)
        #expect(abs(big.width / big.height - 4.0 / 3.0) < 0.02)

        let small = InkInsertion.photoSize(pixels: CGSize(width: 100, height: 50), pageWidth: 816, maxHeight: 500)
        #expect(small == CGSize(width: 50, height: 25))
    }

    private static func writePNG(width: Int, height: Int) throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let data = renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("insert-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    @Test("A big photo is decoded at the size it's kept at, and a small one isn't enlarged")
    func downscaling() throws {
        let big = try Self.writePNG(width: 4000, height: 1000)
        let small = try Self.writePNG(width: 300, height: 200)
        defer {
            try? FileManager.default.removeItem(at: big)
            try? FileManager.default.removeItem(at: small)
        }

        let scaled = try #require(InkInsertion.downscaled(from: big, maxPixelSize: 1632))
        #expect(scaled.width == 1632)
        #expect(scaled.height == 408)

        let kept = try #require(InkInsertion.downscaled(from: small, maxPixelSize: 1632))
        #expect(kept.width == 300)
        #expect(kept.height == 200)
    }

    // MARK: The canvas

    @MainActor
    private final class CanvasHarness {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let textView = DocumentTextView.makeConfiguredTextView()
        let canvas = DrawingCanvas(pageSize: CGSize(width: 816, height: 4224))

        init() {
            textView.frame = window.bounds
            window.addSubview(textView)
            textView.addSubview(canvas)
            window.makeKeyAndVisible()
            canvas.noteSize = CGSize(width: 816, height: 4224)
            canvas.cover(CGRect(x: 0, y: 1200, width: 816, height: 600))
            window.layoutIfNeeded()
        }
    }

    @Test("PaperKit's insert, run around a point, lands there and is one undo, then the canvas is as it was")
    func steeredInsert() throws {
        let harness = CanvasHarness()
        var told = 0
        harness.canvas.onMarkupChanged = { told += 1 }
        let edit = MarkupEditViewController(supportedFeatureSet: .latest)
        let real = harness.canvas.controller.contentVisibleFrame

        harness.canvas.inserting(around: CGPoint(x: 408, y: 2050)) {
            harness.canvas.controller.markupEditViewController(edit, insertNewShape: .rectangle)
        }

        let element = try #require(harness.canvas.markup.subelements.first)
        #expect(abs(element.renderFrame.midY - 2050) < 1)
        #expect(abs(element.renderFrame.midX - 408) < 1)
        #expect(harness.canvas.controller.contentVisibleFrame == real)
        // The page hears of it as it hears of a stroke, so it is kept.
        #expect(told == 1)
        #expect(harness.canvas.undoManager?.canUndo == true)

        harness.canvas.undoManager?.undo()
        #expect(harness.canvas.markup.subelements.isEmpty)
    }

    // MARK: Edits that don't move anything

    private static func shape(fill: UIColor, text: String, id: MarkupID<ShapeMarkup>) -> ShapeMarkup {
        ShapeMarkup(
            shape: .rectangle,
            frame: CGRect(x: 100, y: 300, width: 160, height: 90),
            fillColor: fill.cgColor,
            attributedText: AttributedString(text),
            id: id
        )
    }

    private static func markup(of elements: [any Markup]) -> PaperMarkup {
        var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 100_000))
        markup.subelements.append(contentsOf: elements)
        return markup
    }

    private static func storedShape(_ result: InkCapture.Result) -> ShapeMarkup? {
        for element in result.state.ink.subelements {
            if let shape = element as? ShapeMarkup { return shape }
        }
        return nil
    }

    @Test("A shape recoloured or a text box retyped, where it stands, is taken into the stored ink")
    func editInPlaceIsCaptured() throws {
        let id = MarkupID<ShapeMarkup>()
        let layout = Self.print
        let first = InkCapture.capture(
            Self.markup(of: [Self.shape(fill: .red, text: "hash", id: id)]),
            into: InkCapture.State(ink: PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 100_000))),
            layout: layout, pageCount: 1
        )
        try #require(first.changed)

        // Nothing changed: nothing stored again.
        let same = InkCapture.capture(
            Self.markup(of: [Self.shape(fill: .red, text: "hash", id: id)]),
            into: first.state, layout: layout, pageCount: 1
        )
        #expect(!same.changed)

        let recoloured = InkCapture.capture(
            Self.markup(of: [Self.shape(fill: .blue, text: "hash", id: id)]),
            into: first.state, layout: layout, pageCount: 1
        )
        #expect(recoloured.changed, "a new fill, in the same place, was not taken in")
        #expect(Self.storedShape(recoloured)?.fillColor?.components == UIColor.blue.cgColor.components)

        let retyped = InkCapture.capture(
            Self.markup(of: [Self.shape(fill: .red, text: "hash table", id: id)]),
            into: first.state, layout: layout, pageCount: 1
        )
        #expect(retyped.changed, "new text, in the same place, was not taken in")
        #expect(Self.storedShape(retyped).map { String($0.attributedText.characters) } == "hash table")
        // Still one element, in the place the old one had.
        #expect(Array(retyped.state.ink.subelements).count == 1)
    }

    // MARK: The page

    private static let text = (0..<140).map { "Line \($0): the loop invariant holds." }.joined(separator: "\n")

    @MainActor
    private final class Harness {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1400, height: 1400))
        let page: PageView

        init(layout: PageLayout) {
            let textView = DocumentTextView.makeConfiguredTextView()
            textView.text = InkInsertTests.text
            page = PageView(textView: textView)
            page.pageLayout = layout
            page.frame = CGRect(x: 0, y: 0, width: 880, height: 1100)
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

        func switchTo(_ layout: PageLayout) {
            page.pageLayout = layout
            layOut()
        }

        /// The elements on the canvas.
        var shown: [any Markup] {
            Array(page.canvas.markup.subelements)
        }

        func insertShape(_ type: ShapeConfiguration.Shape = .rectangle) {
            let edit = MarkupEditViewController(supportedFeatureSet: .latest)
            page.insertIntoInk(extent: InkInsertion.shapeExtent) {
                page.canvas.controller.markupEditViewController(edit, insertNewShape: type)
            }
            layOut()
        }
    }

    private static func waitFor(_ condition: () -> Bool, seconds: TimeInterval = 3) async -> Bool {
        let end = Date(timeIntervalSinceNow: seconds)
        while !condition() && Date() < end {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("A shape inserted in seamless is saved where it prints, and is on the same words in every mode")
    func shapeFollowsTheModes() async throws {
        let seamless = PageLayout(orientation: .portrait, mode: .seamless)
        let harness = Harness(layout: seamless)
        var reported: [PaperMarkup] = []
        harness.page.onInkChanged = { reported.append($0) }

        harness.insertShape()

        #expect(await Self.waitFor { !reported.isEmpty })
        let shownAt = try #require(harness.shown.first).renderFrame.midY
        let stored = try #require(reported.last?.subelements.first(where: { $0 is ShapeMarkup }))
        let expected = seamless.convert(y: shownAt, to: Self.print)
        #expect(abs(stored.renderFrame.midY - (expected ?? -1)) < 0.5)

        for mode in [PageViewMode.print, .compressed, .seamless] {
            harness.switchTo(PageLayout(orientation: .portrait, mode: mode))
            let layout = harness.page.pageLayout
            let element = try #require(harness.shown.first)
            let want = seamless.convert(y: shownAt, to: layout)
            #expect(abs(element.renderFrame.midY - (want ?? -1)) < 0.5, "\(mode)")
        }
    }

    @Test("Inserting in print layout with a break in the middle of the screen puts the element on a page")
    func insertAvoidsTheBreak() async throws {
        let harness = Harness(layout: Self.print)
        let regions = Self.print.inkRegions(pageCount: harness.page.pageCount)
        try #require(regions.count > 1)
        let gap = (regions[0].maxY + regions[1].minY) / 2
        // Scrolled so the middle of the screen is in the gap between sheets.
        let height = harness.page.textView.bounds.height
        harness.page.textView.contentOffset.y = gap - height / 2
        harness.layOut()
        let visible = harness.page.canvas.coveredPart
        try #require(abs(visible.midY - gap) < 2, "scrolled to \(visible), wanted the middle at \(gap)")

        harness.insertShape()

        let element = try #require(harness.shown.first)
        #expect(Self.print.takesInk(at: CGPoint(x: element.renderFrame.midX, y: element.renderFrame.midY), pageCount: harness.page.pageCount))
        #expect(regions.contains { $0.insetBy(dx: 0, dy: -1).contains(element.renderFrame) }, "\(element.renderFrame)")
    }

    @Test("A shape, a text box and a photo survive saving, reopening and the PDF")
    func survivesSavingAndPrinting() async throws {
        let seamless = PageLayout(orientation: .portrait, mode: .seamless)
        let harness = Harness(layout: seamless)
        var reported = 0
        harness.page.onInkChanged = { _ in reported += 1 }
        let edit = MarkupEditViewController(supportedFeatureSet: .latest)
        let controller = harness.page.canvas.controller

        harness.insertShape()
        harness.page.insertIntoInk(extent: InkInsertion.shapeExtent) {
            controller.markupEditViewController(edit, insertNewShape: .ellipse)
        }
        harness.page.insertIntoInk(extent: InkInsertion.shapeExtent) {
            controller.markupEditViewControllerInsertNewTextbox(edit)
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let photo = try #require(renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }.cgImage)
        var contents = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        contents.insertNewImage(photo, frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        harness.page.insertIntoInk(extent: CGSize(width: 200, height: 200)) {
            controller.markupEditViewController(edit, insertNewContents: contents)
        }
        harness.layOut()

        let before = harness.shown
        try #require(before.count == 4, "\(before.map { type(of: $0) })")
        #expect(await Self.waitFor { reported > 0 })
        harness.page.commitInk()

        // Saved and read back, as a note is.
        let data = try await DrawingCodec.encode(harness.page.ink)
        guard case .ink(let reopened) = DrawingCodec.decode(data) else {
            Issue.record("the saved ink couldn't be read")
            return
        }
        let kinds = Array(reopened.subelements).map { String(describing: type(of: $0)) }.sorted()
        #expect(kinds == ["ImageMarkup", "ShapeMarkup", "ShapeMarkup", "ShapeMarkup"], "\(kinds)")

        // Reopened on a page, in another mode, the image is where it was.
        let again = Harness(layout: Self.print)
        again.page.setInk(reopened)
        again.layOut()
        let image = try #require(again.shown.first { $0 is ImageMarkup })
        let stored = try #require(harness.page.ink.subelements.first { $0 is ImageMarkup })
        #expect(abs(image.renderFrame.midY - stored.renderFrame.midY) < 0.5)
        #expect(abs(image.renderFrame.width - stored.renderFrame.width) < 0.5)

        // And printed: the red photo is on its sheet, the right way up.
        let layout = Self.print
        let pdfData = await NotePDF.render(NotePDF.Note(
            title: "Note", text: Self.text, ink: harness.page.ink, orientation: .portrait, pageCount: harness.page.pageCount
        ))
        let pdf = try #require(PDFDocument(data: pdfData))
        let sheetIndex = layout.pageIndex(atY: stored.renderFrame.midY)
        let bitmap = try #require(Bitmap(pdfPage: pdf.page(at: sheetIndex)))
        let sheet = layout.sheet(ofPage: sheetIndex)
        let scale = NotePDF.pointsPerPagePoint
        let onSheet = CGPoint(x: stored.renderFrame.midX * scale, y: (stored.renderFrame.midY - sheet.minY) * scale)
        // `Bitmap` reads from the top, as the page reads.
        #expect(bitmap.luminance(at: onSheet) < 0.5, "the photo didn't print at \(onSheet)")
        // And the right way up: not at the same distance from the bottom.
        let upsideDown = CGPoint(x: onSheet.x, y: 792 - onSheet.y)
        if abs(upsideDown.y - onSheet.y) > 60 {
            #expect(bitmap.luminance(at: upsideDown) > 0.95, "the photo printed upside down")
        }
        #expect(bitmap.luminance(at: CGPoint(x: 30, y: 30)) > 0.95)
    }

    @Test("Undo takes an inserted element off the page")
    func insertIsUndoable() async throws {
        let harness = Harness(layout: PageLayout(orientation: .portrait, mode: .seamless))
        var reported = 0
        harness.page.onInkChanged = { _ in reported += 1 }

        harness.insertShape()
        #expect(await Self.waitFor { reported == 1 })
        try #require(harness.page.canvas.undoManager?.canUndo == true)

        harness.page.canvas.undoManager?.undo()
        harness.layOut()

        #expect(harness.shown.isEmpty)
        #expect(await Self.waitFor { reported == 2 })
        #expect(Array(harness.page.ink.subelements).isEmpty)
    }

    // MARK: The popover

    @Test("The button lets go when the popover goes by a route the delegates don't see, and opens it again")
    func popoverStateFollowsTheController() async throws {
        let window = HotbarLayoutTests.makeWindow()
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        let anchor = UIView(frame: CGRect(x: 100, y: 100, width: 40, height: 40))
        host.view.addSubview(anchor)

        let editor = NoteEditor()
        editor.setMode(.ink)
        let inserter = InkInserter()
        inserter.anchorView = anchor

        inserter.present(for: editor)
        #expect(inserter.isPresented)
        #expect(await Self.waitFor { host.presentedViewController is MarkupEditViewController })

        // PaperKit's nested pickers can take the popover away without a
        // callback to the delegates; dismissing it directly is that.
        host.dismiss(animated: false)
        #expect(await Self.waitFor { !inserter.isPresented })

        inserter.present(for: editor)
        #expect(inserter.isPresented)
        #expect(await Self.waitFor { host.presentedViewController is MarkupEditViewController })
        host.dismiss(animated: false)
    }
}

#endif
