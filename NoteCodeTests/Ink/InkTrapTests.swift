//
//  InkTrapTests.swift
//  NoteCodeTests
//
//  AGENTS.md › Implementation requirements: never read `PKInk.inkType` from a
//  stroke the canvas made. PaperKit's pixel eraser adds a stroke in
//  `com.apple.ink.eraser`, which `PKInk.InkType` has no case for, and the
//  Swift getter traps on it. `lint-traps.sh` rule 2 keeps the getter out of
//  the app; these check that what the app uses instead handles that ink.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Eraser ink trap", .tags(.ink))
struct InkTrapTests {

    private static let eraserID = "com.apple.ink.eraser"

    private static func eraserInk() -> PKInk {
        PKInkReference(inkType: __PKInkType(rawValue: eraserID), color: .clear) as PKInk
    }

    private static func stroke(ink: PKInk) -> PKStroke {
        let points = (0..<4).map { index in
            PKStrokePoint(location: CGPoint(x: 100 + Double(index) * 20, y: 100), timeOffset: Double(index) * 0.01,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    @Test("inkIdentifier names the eraser's ink, and a pen's")
    func identifierNamesEraserInk() {
        #expect(InkContent.inkIdentifier(of: Self.eraserInk()) == Self.eraserID)
        #expect(InkContent.inkIdentifier(of: PKInk(.pen, color: .black)) == PKInk.InkType.pen.rawValue)
    }

    @Test("A pixel eraser's stroke can be signed, and signs differently from a pen's")
    func signatureSurvivesEraser() {
        let eraser = Self.stroke(ink: Self.eraserInk())
        let pen = Self.stroke(ink: PKInk(.pen, color: .black))
        #expect(InkContent.inkSignature(of: eraser) != InkContent.inkSignature(of: pen))
    }

    @Test("Recolouring leaves the eraser's stroke erasing")
    func recolourLeavesEraser() {
        let eraser = Self.stroke(ink: Self.eraserInk())
        let result = InkCommands.recoloured(eraser, to: .red)
        #expect(InkContent.inkIdentifier(of: result.ink) == Self.eraserID)
    }
}

#endif
