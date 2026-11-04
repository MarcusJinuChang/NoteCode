//
//  InkObjectCommandTests.swift
//  NoteCodeTests
//
//  Step 2 of docs/design/object-system.md: what a selection shape touches, and
//  the commands that change it.
//

#if canImport(UIKit)

import Foundation
import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Ink objects and commands")
@MainActor
struct InkObjectCommandTests {

    typealias ElementID = MarkupOrderedSet.ElementID

    private static func stroke(from start: CGPoint, to end: CGPoint, id: UUID = UUID(), color: UIColor = .black) -> PKStroke {
        let points = (0...10).map { i -> PKStrokePoint in
            let t = CGFloat(i) / 10
            return PKStrokePoint(
                location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                timeOffset: TimeInterval(i) * 0.01, size: CGSize(width: 2, height: 2),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        var stroke = PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)))
        stroke.id = id
        return stroke
    }

    private static func markup(_ elements: [any Markup]) -> PaperMarkup {
        var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 1056))
        markup.subelements.append(contentsOf: elements)
        return markup
    }

    private static func rectangle(_ frame: CGRect) -> ShapeMarkup {
        ShapeMarkup(shape: .rectangle, frame: frame, strokeColor: UIColor.black.cgColor)
    }

    private static func ids(_ markup: PaperMarkup) -> [ElementID] {
        var ids: [ElementID] = []
        for element in markup.subelements { ids.append(element.elementID) }
        return ids
    }

    // MARK: Hit testing

    @Test("A rectangle selects the strokes it touches and leaves the rest")
    func rectangleTouches() {
        let through = Self.stroke(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 250, y: 100))
        let inside = Self.stroke(from: CGPoint(x: 120, y: 90), to: CGPoint(x: 140, y: 110))
        let outside = Self.stroke(from: CGPoint(x: 50, y: 400), to: CGPoint(x: 250, y: 400))
        let note = Self.markup([through, inside, outside])

        let hit = InkObjects.select(.rectangle(CGRect(x: 100, y: 80, width: 80, height: 40)), in: note)

        #expect(hit == [through.elementID, inside.elementID])
    }

    @Test("Touching the bounding box of a stroke, but not the stroke, selects nothing")
    func emptyCornerOfTheBox() {
        let diagonal = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 300))
        let note = Self.markup([diagonal])

        let corner = InkObjects.select(.rectangle(CGRect(x: 250, y: 110, width: 40, height: 40)), in: note)
        let line = InkObjects.select(.rectangle(CGRect(x: 190, y: 190, width: 20, height: 20)), in: note)

        #expect(corner.isEmpty)
        #expect(line == [diagonal.elementID])
    }

    @Test("A lasso selects what is inside its loop")
    func lassoLoop() {
        let inLoop = Self.stroke(from: CGPoint(x: 150, y: 150), to: CGPoint(x: 160, y: 160))
        let away = Self.stroke(from: CGPoint(x: 600, y: 600), to: CGPoint(x: 650, y: 650))
        let note = Self.markup([inLoop, away])
        let triangle = SelectionShape.lasso([CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 120), CGPoint(x: 200, y: 300)])

        #expect(InkObjects.select(triangle, in: note) == [inLoop.elementID])
        #expect(!triangle.contains(CGPoint(x: 120, y: 280)))
        #expect(triangle.contains(CGPoint(x: 200, y: 180)))
    }

    @Test("A tap-sized rectangle picks the one stroke under it, not its neighbours")
    func tapPicksOne() {
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        let b = Self.stroke(from: CGPoint(x: 100, y: 130), to: CGPoint(x: 200, y: 130))
        let note = Self.markup([a, b])

        let hit = InkObjects.select(.rectangle(CGRect(x: 147, y: 97, width: 6, height: 6)), in: note)

        #expect(hit == [a.elementID])
    }

    @Test("A stroke across a page break is one object: touching one piece takes them all")
    func familySelectsTogether() {
        let first = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100))
        let family = InkPages.family(of: first.id)
        let piece = Self.stroke(from: CGPoint(x: 100, y: 900), to: CGPoint(x: 300, y: 900), id: InkPages.overflowID(in: family))
        let other = Self.stroke(from: CGPoint(x: 100, y: 500), to: CGPoint(x: 300, y: 500))
        let note = Self.markup([first, other, piece])

        let hit = InkObjects.select(.rectangle(CGRect(x: 150, y: 90, width: 20, height: 20)), in: note)

        #expect(hit == [first.elementID, piece.elementID])
    }

    @Test("A shape or an image is selected by its frame")
    func shapeByFrame() {
        let shape = Self.rectangle(CGRect(x: 300, y: 300, width: 100, height: 100))
        let note = Self.markup([shape])

        #expect(InkObjects.select(.rectangle(CGRect(x: 390, y: 390, width: 30, height: 30)), in: note) == [ElementID(shape.id)])
        #expect(InkObjects.select(.rectangle(CGRect(x: 420, y: 420, width: 30, height: 30)), in: note).isEmpty)
        let around = SelectionShape.lasso([CGPoint(x: 250, y: 250), CGPoint(x: 450, y: 250), CGPoint(x: 450, y: 450), CGPoint(x: 250, y: 450)])
        #expect(InkObjects.select(around, in: note) == [ElementID(shape.id)])
    }

    // MARK: Commands

    @Test("Move shifts the chosen objects only, keeps every id and the order")
    func moveKeepsIdentity() {
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        let shape = Self.rectangle(CGRect(x: 300, y: 300, width: 50, height: 50))
        let b = Self.stroke(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 200, y: 200))
        let note = Self.markup([a, shape, b])

        let moved = InkCommands.transformed(note, ids: [a.elementID, ElementID(shape.id)], by: CGAffineTransform(translationX: 40, y: 30))

        // The set keeps its own order (strokes and shapes aren't interleaved
        // as they were handed in); a command must not change it.
        #expect(Self.ids(moved) == Self.ids(note))
        var frames: [ElementID: CGRect] = [:]
        for element in moved.subelements { frames[element.elementID] = element.renderFrame }
        #expect(abs(frames[a.elementID]!.minX - (a.renderFrame.minX + 40)) < 0.5)
        #expect(abs(frames[ElementID(shape.id)]!.minY - (shape.renderFrame.minY + 30)) < 0.5)
        #expect(frames[b.elementID] == b.renderFrame)
    }

    @Test("Recolour changes the ink and nothing else, under the same id and in the same place")
    func recolourKeepsIdentity() throws {
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100), color: .black)
        let shape = Self.rectangle(CGRect(x: 300, y: 300, width: 50, height: 50))
        let note = Self.markup([a, shape])

        let red = InkCommands.recoloured(note, ids: [a.elementID, ElementID(shape.id)], to: .red)

        #expect(Self.ids(red) == Self.ids(note))
        var found: PKStroke?
        var recoloured: ShapeMarkup?
        for element in red.subelements {
            if let stroke = element as? PKStroke { found = stroke }
            if let shape = element as? ShapeMarkup { recoloured = shape }
        }
        let stroke = try #require(found)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        stroke.ink.color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        #expect(r > 0.9 && g < 0.2)
        #expect(stroke.ink.inkType == PKInk.InkType.pen)
        #expect(stroke.renderFrame == a.renderFrame)
        #expect(stroke.id == a.id)
        #expect(try #require(recoloured).strokeColor == UIColor.red.cgColor)
    }

    @Test("Recolour leaves a pixel eraser's stroke erasing")
    func recolourKeepsEraser() throws {
        // PaperKit's pixel eraser adds a stroke in an ink `PKInk.InkType`
        // has no case for, and the Select tool can take it with the ink.
        var eraser = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        eraser.ink = PKInkReference(inkType: __PKInkType(rawValue: "com.apple.ink.eraser"), color: .clear) as PKInk
        var note = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 1056))
        note.subelements.append(contentsOf: [eraser])

        let red = InkCommands.recoloured(note, ids: [eraser.elementID], to: .red)

        var found: PKStroke?
        for element in red.subelements {
            found = element as? PKStroke
        }
        let stroke = try #require(found)
        #expect((stroke.ink as PKInkReference).inkType.rawValue == "com.apple.ink.eraser")
        #expect(stroke.id == eraser.id)
    }

    @Test("Delete takes the chosen objects and no others")
    func deleteTakes() {
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        let b = Self.stroke(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 200, y: 200))
        let note = Self.markup([a, b])

        let after = InkCommands.deleted(note, ids: [a.elementID])

        #expect(Self.ids(after) == [b.elementID])
    }

    @Test("Duplicate adds copies on top, offset, under new ids, a stroke's pieces under one new family")
    func duplicateCopies() throws {
        let a = Self.stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        let piece = Self.stroke(from: CGPoint(x: 100, y: 900), to: CGPoint(x: 200, y: 900), id: InkPages.overflowID(in: InkPages.family(of: a.id)))
        let shape = Self.rectangle(CGRect(x: 300, y: 300, width: 50, height: 50))
        let note = Self.markup([a, piece, shape])

        let (after, copies) = InkCommands.duplicated(note, ids: [a.elementID, piece.elementID, ElementID(shape.id)], offset: CGSize(width: 20, height: 20))

        let all = Self.ids(after)
        let originals = Self.ids(note)
        #expect(all.count == 6)
        #expect(all.filter { originals.contains($0) } == originals, "the originals keep their places")
        #expect(copies.count == 3)
        #expect(copies.isDisjoint(with: Set(originals)))
        let strokeCopies = after.subelements.compactMap { copies.contains($0.elementID) ? $0 as? PKStroke : nil }
        #expect(strokeCopies.count == 2)
        #expect(InkPages.family(of: strokeCopies[0].id) == InkPages.family(of: strokeCopies[1].id))
        #expect(InkPages.family(of: strokeCopies[0].id) != InkPages.family(of: a.id))
        #expect(InkPages.isOverflow(strokeCopies[1].id) && !InkPages.isOverflow(strokeCopies[0].id))
        #expect(abs(strokeCopies[0].renderFrame.minX - (a.renderFrame.minX + 20)) < 0.5)
    }

    @Test("A command on 5,000 strokes is one rebuild, not one edit per object")
    func cost() {
        var elements: [any Markup] = []
        for i in 0..<5_000 {
            elements.append(Self.stroke(from: CGPoint(x: CGFloat(i % 40) * 20, y: CGFloat(i / 40) * 8), to: CGPoint(x: CGFloat(i % 40) * 20 + 15, y: CGFloat(i / 40) * 8 + 4)))
        }
        let note = Self.markup(elements)
        var chosen: Set<ElementID> = []
        for (index, element) in note.subelements.enumerated() where index < 200 { chosen.insert(element.elementID) }

        let start = ContinuousClock.now
        let moved = InkCommands.transformed(note, ids: chosen, by: CGAffineTransform(translationX: 10, y: 10))
        let elapsed = ContinuousClock.now - start

        #expect(moved.subelements.count == 5_000)
        #expect(elapsed < .seconds(2), "moving 200 of 5,000 took \(elapsed): per-element edits, which cost 1.7s for 114")
    }
}

#endif
