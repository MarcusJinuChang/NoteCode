//
//  InkSelectionTests.swift
//  NoteCodeTests
//
//  Step 3 of docs/design/object-system.md: the Select tool's state, its
//  commands on a real canvas, and who owns touches.
//

#if canImport(UIKit)

import Foundation
import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Select tool")
@MainActor
struct InkSelectionTests {

    typealias ElementID = MarkupOrderedSet.ElementID

    /// The page, its editor and the canvas, in a window, in ink mode.
    @MainActor
    private final class Rig {
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let textView = DocumentTextView.makeConfiguredTextView()
        let editor = NoteEditor()
        let page: PageView
        var canvas: DrawingCanvas { page.canvas }
        var selection: InkSelection { page.selection }
        /// Times the canvas told its delegate the markup changed.
        var notifications = 0

        init() {
            page = PageView(textView: textView)
            page.frame = window.bounds
            window.addSubview(page)
            window.makeKeyAndVisible()
            page.layoutIfNeeded()
            editor.attach(textView, canvas: page.canvas, page: page)
            editor.setMode(.ink)
            let previous = canvas.onMarkupChanged
            canvas.onMarkupChanged = { [unowned self] in
                notifications += 1
                previous?()
            }
        }

        func put(_ elements: [any Markup]) {
            var markup = canvas.markup
            markup.subelements.append(contentsOf: elements)
            canvas.markup = markup
        }

        func frames() -> [ElementID: CGRect] {
            var frames: [ElementID: CGRect] = [:]
            for element in canvas.markup.subelements { frames[element.elementID] = element.renderFrame }
            return frames
        }
    }

    private static func stroke(from start: CGPoint, to end: CGPoint) -> PKStroke {
        let points = (0...10).map { i -> PKStrokePoint in
            let t = CGFloat(i) / 10
            return PKStrokePoint(
                location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                timeOffset: TimeInterval(i) * 0.01, size: CGSize(width: 2, height: 2),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)))
    }

    // MARK: What a touch does

    @Test("Where a touch lands decides whether it moves, scales or draws")
    func touchDecision() {
        let box = CGRect(x: 100, y: 100, width: 200, height: 100)

        #expect(SelectionTouch.decide(at: CGPoint(x: 500, y: 500), selection: nil, canScale: true) == .draw)
        #expect(SelectionTouch.decide(at: CGPoint(x: 150, y: 150), selection: box, canScale: true) == .move)
        #expect(SelectionTouch.decide(at: CGPoint(x: 305, y: 150), selection: box, canScale: true) == .move)
        #expect(SelectionTouch.decide(at: CGPoint(x: 340, y: 150), selection: box, canScale: true) == .draw)
        #expect(SelectionTouch.decide(at: CGPoint(x: 300, y: 200), selection: box, canScale: true) == .scale)
        #expect(SelectionTouch.decide(at: CGPoint(x: 300, y: 200), selection: box, canScale: false) == .move)
    }

    // MARK: Choosing

    @Test("Selecting takes what the shape touches and boxes it")
    func selects() {
        let rig = Rig()
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        let b = Self.stroke(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 200, y: 400))
        rig.put([a, b])

        #expect(rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20))))

        #expect(rig.selection.ids == [a.elementID])
        let box = rig.selection.bounds
        #expect(box == a.renderFrame)
        #expect(!rig.selection.select(.rectangle(CGRect(x: 500, y: 500, width: 10, height: 10))))
    }

    // MARK: Commands

    @Test("Move shifts the selection, tells the page once, and undoes and redoes as one step")
    func moveAndUndo() {
        let rig = Rig()
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        let b = Self.stroke(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 200, y: 400))
        rig.put([a, b])
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        let before = rig.frames()
        rig.notifications = 0

        rig.selection.move(by: CGSize(width: 30, height: 40))

        var moved = rig.frames()
        #expect(abs(moved[a.elementID]!.minX - (before[a.elementID]!.minX + 30)) < 0.5)
        #expect(moved[b.elementID] == before[b.elementID])
        #expect(rig.notifications > 0, "the page must hear of the change, or it is never stored")
        #expect(rig.selection.bounds == moved[a.elementID])

        rig.editor.undo()
        #expect(rig.frames() == before)
        #expect(rig.selection.bounds == before[a.elementID], "the box follows an undo")

        rig.editor.redo()
        moved = rig.frames()
        #expect(abs(moved[a.elementID]!.minX - (before[a.elementID]!.minX + 30)) < 0.5)
    }

    @Test("A drag shows the move without telling the page, then commits once")
    func dragCommitsOnce() {
        let rig = Rig()
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        rig.put([a])
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        let start = rig.frames()
        rig.notifications = 0

        rig.selection.beginAdjusting()
        rig.selection.previewMove(by: CGSize(width: 10, height: 0))
        rig.selection.previewMove(by: CGSize(width: 25, height: 5))
        #expect(rig.notifications == 0, "a drag in progress isn't a change yet")
        #expect(abs(rig.frames()[a.elementID]!.minX - (start[a.elementID]!.minX + 25)) < 0.5)

        rig.selection.endAdjusting(actionName: "Move")

        #expect(rig.notifications > 0)
        #expect(abs(rig.frames()[a.elementID]!.minX - (start[a.elementID]!.minX + 25)) < 0.5)
        rig.editor.undo()
        #expect(rig.frames() == start, "one undo takes the whole drag")
    }

    @Test("A drag that is cancelled, or goes nowhere, leaves the canvas and the undo stack as they were")
    func dragCancels() {
        let rig = Rig()
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        rig.put([a])
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        let start = rig.frames()
        rig.notifications = 0

        rig.selection.beginAdjusting()
        rig.selection.previewMove(by: CGSize(width: 40, height: 40))
        rig.selection.cancelAdjusting()
        #expect(rig.frames() == start)

        rig.selection.beginAdjusting()
        rig.selection.endAdjusting(actionName: "Move")
        #expect(rig.frames() == start)
        #expect(rig.notifications == 0)
        #expect(!rig.editor.canUndo)
    }

    @Test("A scale grows the selection about its corner")
    func scales() {
        let rig = Rig()
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        rig.put([a])
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        let box = try! #require(rig.selection.bounds)

        rig.selection.beginAdjusting()
        rig.selection.previewScale(by: 2)
        rig.selection.endAdjusting(actionName: "Resize")

        let after = try! #require(rig.selection.bounds)
        // Scaled about the corner of its frame, give or take the ink's own
        // thickness, which isn't exactly proportional.
        #expect(abs(after.minX - box.minX) < 3 && abs(after.minY - box.minY) < 3)
        #expect(after.width > box.width * 1.8 && after.width < box.width * 2.2)
    }

    @Test("Recolour, duplicate and delete are each one undo step, and delete ends the selection")
    func commands() throws {
        let rig = Rig()
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        rig.put([a])
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        var ended = 0
        rig.selection.onEnded = { ended += 1 }

        rig.selection.recolour(to: .red)
        let red = try #require(rig.canvas.markup.subelements.first as? PKStroke)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        red.ink.color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        #expect(r > 0.9 && g < 0.2)
        rig.editor.undo()
        let black = try #require(rig.canvas.markup.subelements.first as? PKStroke)
        black.ink.color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        #expect(r < 0.1)

        rig.selection.duplicate()
        #expect(rig.canvas.markup.subelements.count == 2)
        #expect(rig.selection.ids.count == 1 && !rig.selection.ids.contains(a.elementID), "the copies are what is selected")
        rig.editor.undo()
        #expect(rig.canvas.markup.subelements.count == 1)

        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        rig.selection.delete()
        #expect(rig.canvas.markup.subelements.isEmpty)
        #expect(rig.selection.isEmpty)
        #expect(ended == 1)
        rig.editor.undo()
        #expect(rig.canvas.markup.subelements.count == 1)
    }

    // MARK: Who owns touches

    @Test("The overlay owns touches only while the Select tool is current in ink mode")
    func inputOwnership() {
        let rig = Rig()
        let point = CGPoint(x: 100, y: 100)
        rig.page.layoutIfNeeded()
        rig.page.selectionOverlay.cover(CGRect(x: 0, y: 0, width: 816, height: 600))

        rig.editor.inkTool.kind = .pen
        #expect(!rig.page.selectionOverlay.isUserInteractionEnabled)
        #expect(!rig.page.selectionOverlay.point(inside: point, with: nil))

        rig.editor.inkTool.kind = .lasso
        #expect(rig.page.selectionOverlay.isUserInteractionEnabled)
        #expect(rig.page.selectionOverlay.point(inside: point, with: nil))

        rig.editor.setMode(.text)
        #expect(!rig.page.selectionOverlay.isUserInteractionEnabled, "text mode owns the page")

        rig.editor.setMode(.ink)
        #expect(rig.page.selectionOverlay.isUserInteractionEnabled)

        rig.editor.inkTool.kind = .eraser
        #expect(!rig.page.selectionOverlay.isUserInteractionEnabled)
    }

    @Test("Leaving the Select tool, or ink mode, lets go of the selection")
    func letsGo() {
        let rig = Rig()
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        rig.put([a])
        rig.editor.inkTool.kind = .lasso
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        #expect(!rig.selection.isEmpty)

        rig.editor.inkTool.kind = .pen
        #expect(rig.selection.isEmpty)

        rig.editor.inkTool.kind = .lasso
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        rig.editor.setMode(.text)
        #expect(rig.selection.isEmpty)
    }

    @Test("A finger doesn't select when the canvas is locked to the Pencil")
    func pencilLock() {
        let rig = Rig()
        rig.editor.inkTool.kind = .lasso
        rig.editor.isPencilOnly = true
        #expect(!rig.page.selectionOverlay.allowsFingers)
        rig.editor.isPencilOnly = false
        #expect(rig.page.selectionOverlay.allowsFingers)
    }

    // MARK: Storing a recolour

    /// What `PageView` records of a markup it shows.
    private static func table(of markup: PaperMarkup) -> (frames: [ElementID: CGRect], contents: [ElementID: Int]) {
        var frames: [ElementID: CGRect] = [:]
        var contents: [ElementID: Int] = [:]
        for element in markup.subelements {
            frames[element.elementID] = element.renderFrame
            if let fingerprint = InkContent.fingerprint(of: element) { contents[element.elementID] = fingerprint }
        }
        return (frames, contents)
    }

    private func colour(of stroke: PKStroke) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        stroke.ink.color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        return r
    }

    private func stored(_ markup: PaperMarkup) -> [PKStroke] {
        var strokes: [PKStroke] = []
        for element in markup.subelements { if let stroke = element as? PKStroke { strokes.append(stroke) } }
        return strokes
    }

    @Test("A recolour is stored: same id and same frame, and the capture still sees it")
    func recolourIsCaptured() throws {
        let layout = PageLayout(orientation: .portrait, mode: .print)
        let a = Self.stroke(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 300, y: 200))
        var ink = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 1056, height: layout.noteHeight(pageCount: 1)))
        ink.subelements.append(a)
        let (frames, contents) = Self.table(of: ink)
        let state = InkCapture.State(ink: ink, shown: frames, contents: contents)

        let untouched = InkCapture.capture(ink, into: state, layout: layout, pageCount: 1)
        #expect(!untouched.changed)

        let red = InkCommands.recoloured(ink, ids: [a.elementID], to: .red)
        let result = InkCapture.capture(red, into: state, layout: layout, pageCount: 1)

        #expect(result.changed, "a recolour moves nothing, so a frame alone can't see it")
        let kept = stored(result.state.ink)
        #expect(kept.count == 1)
        #expect(kept.first?.id == a.id)
        #expect(try colour(of: #require(kept.first)) > 0.9)
    }

    @Test("A recolour reaches the part of a stroke the canvas doesn't show")
    func recolourReachesHiddenOverflow() throws {
        let layout = PageLayout(orientation: .portrait, mode: .print)
        let regions = layout.inkRegions(pageCount: 2)
        let own = Self.stroke(from: CGPoint(x: 200, y: regions[0].midY), to: CGPoint(x: 300, y: regions[0].midY))
        var overflow = Self.stroke(from: CGPoint(x: 200, y: regions[1].midY), to: CGPoint(x: 300, y: regions[1].midY))
        overflow.id = InkPages.overflowID(in: InkPages.family(of: own.id))

        let height = layout.noteHeight(pageCount: 2)
        var stored = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 1056, height: height))
        stored.subelements.append(contentsOf: [own, overflow])
        var canvas = PaperMarkup(bounds: stored.bounds)
        canvas.subelements.append(own)
        let (frames, contents) = Self.table(of: canvas)
        let state = InkCapture.State(ink: stored, shown: frames, contents: contents)

        let result = InkCapture.capture(InkCommands.recoloured(canvas, ids: [own.elementID], to: .red), into: state, layout: layout, pageCount: 2)

        let kept = self.stored(result.state.ink)
        #expect(kept.count == 2)
        #expect(kept.allSatisfy { colour(of: $0) > 0.9 }, "the hidden piece must change colour with the shown one")
    }

    // MARK: Previous tool

    @Test("With the setting on, Delete and a tap on empty space go back to the tool before Select")
    func returnsAfterTheSelectionEnds() {
        let rig = Rig()
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        rig.put([a])
        rig.editor.returnsToPreviousTool = true
        rig.editor.inkTool.kind = .highlighter
        rig.editor.inkTool.kind = .lasso

        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        rig.selection.delete()
        #expect(rig.editor.inkTool.kind == .highlighter)

        rig.editor.undo()
        rig.editor.inkTool.kind = .lasso
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        rig.page.selectionOverlay.beginsDrawingForTest()
        rig.page.selectionOverlay.completeDrawing(with: .rectangle(CGRect(x: 600, y: 600, width: 8, height: 8)))
        #expect(rig.editor.inkTool.kind == .highlighter, "a tap on empty space ends the selection")
    }

    @Test("Off, nothing returns; and a tool switch, a move or a recolour never does")
    func neverReturnsOtherwise() {
        let rig = Rig()
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        rig.put([a])
        rig.editor.inkTool.kind = .highlighter
        rig.editor.inkTool.kind = .lasso
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        rig.selection.delete()
        #expect(rig.editor.inkTool.kind == .lasso, "setting off: the Select tool stays")

        rig.editor.returnsToPreviousTool = true
        rig.editor.undo()
        rig.selection.select(.rectangle(CGRect(x: 120, y: 90, width: 30, height: 20)))
        rig.selection.move(by: CGSize(width: 10, height: 10))
        rig.selection.recolour(to: .red)
        rig.selection.duplicate()
        #expect(rig.editor.inkTool.kind == .lasso)

        rig.editor.inkTool.kind = .eraser
        #expect(rig.editor.inkTool.kind == .eraser, "the reader chose the eraser")
    }

    @Test("Insert hands what it inserted to the Select tool")
    func insertSelects() throws {
        let rig = Rig()

        _ = rig.editor.insertIntoInk(extent: CGSize(width: 100, height: 80)) { controller in
            var markup = controller.markup ?? PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 1056))
            markup.insertNewShape(configuration: ShapeConfiguration(type: .rectangle), frame: CGRect(x: 100, y: 100, width: 100, height: 80))
            controller.markup = markup
        }

        #expect(rig.editor.inkTool.kind == .lasso)
        #expect(rig.selection.ids.count == 1)
        #expect(rig.canvas.controller.selection.isEmpty, "PaperKit's own selection is let go")
    }
}

#endif
