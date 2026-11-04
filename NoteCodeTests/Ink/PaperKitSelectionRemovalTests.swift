//
//  PaperKitSelectionRemovalTests.swift
//  NoteCodeTests
//
//  Step 6 of docs/design/object-system.md: PaperKit's own selection is gone
//  except for one object the reader chose to Edit.
//

#if canImport(UIKit)

import Foundation
import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("PaperKit's selection")
@MainActor
struct PaperKitSelectionRemovalTests {

    @MainActor
    private final class Rig {
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let textView = DocumentTextView.makeConfiguredTextView()
        let editor = NoteEditor()
        let page: PageView
        var canvas: DrawingCanvas { page.canvas }
        var shapeID: MarkupOrderedSet.ElementID

        init() {
            page = PageView(textView: textView)
            page.frame = window.bounds
            window.addSubview(page)
            window.makeKeyAndVisible()
            page.layoutIfNeeded()
            editor.attach(textView, canvas: page.canvas, page: page)
            editor.setMode(.ink)
            var markup = page.canvas.markup
            markup.insertNewShape(configuration: ShapeConfiguration(type: .rectangle), frame: CGRect(x: 100, y: 100, width: 100, height: 80))
            page.canvas.markup = markup
            shapeID = page.canvas.markup.subelements.first!.elementID
        }
    }

    @Test("A selection PaperKit makes on its own is let go of at once")
    func foreignSelectionIsCleared() {
        let rig = Rig()
        rig.editor.inkTool.kind = .pen
        // PaperKit tells its delegate as the selection is set, on the same
        // call, so it is already gone when the assignment returns.
        rig.canvas.controller.selection = [rig.shapeID]

        #expect(rig.canvas.controller.selection.isEmpty)
    }

    @Test("PaperKit gets no touches while the Select tool has the page")
    func inputIsSuspended() {
        let rig = Rig()
        #expect(rig.canvas.controller.view.isUserInteractionEnabled)

        rig.editor.inkTool.kind = .lasso
        #expect(!rig.canvas.controller.view.isUserInteractionEnabled)

        rig.editor.inkTool.kind = .pen
        #expect(rig.canvas.controller.view.isUserInteractionEnabled)

        rig.editor.inkTool.kind = .lasso
        rig.editor.setMode(.text)
        #expect(rig.canvas.controller.view.isUserInteractionEnabled, "text mode hands the page back")
    }

    @Test("One shape can be handed to PaperKit to edit, and handed back")
    func editBridge() {
        let rig = Rig()
        rig.editor.inkTool.kind = .lasso
        let selection = rig.page.selection
        selection.select(.rectangle(CGRect(x: 120, y: 120, width: 20, height: 20)))
        #expect(selection.canEditInPaperKit)

        selection.editInPaperKit()
        #expect(rig.canvas.controller.selection == [rig.shapeID])
        #expect(rig.canvas.controller.selection == [rig.shapeID], "an edit in progress isn't let go of")
        #expect(rig.canvas.controller.view.isUserInteractionEnabled)
        #expect(!rig.page.selectionOverlay.isUserInteractionEnabled, "PaperKit has the touches while it edits")

        selection.finishEditingInPaperKit()
        #expect(rig.canvas.controller.selection.isEmpty)
        #expect(!rig.canvas.controller.view.isUserInteractionEnabled)
        #expect(rig.page.selectionOverlay.isUserInteractionEnabled)
    }

    @Test("Leaving the Select tool ends an edit")
    func toolSwitchEndsEdit() {
        let rig = Rig()
        rig.editor.inkTool.kind = .lasso
        rig.page.selection.select(.rectangle(CGRect(x: 120, y: 120, width: 20, height: 20)))
        rig.page.selection.editInPaperKit()

        rig.editor.inkTool.kind = .pen

        #expect(!rig.page.selection.isEditingInPaperKit)
        #expect(rig.canvas.controller.selection.isEmpty)
        // And the next foreign selection is let go of again.
        rig.canvas.controller.selection = [rig.shapeID]
        #expect(rig.canvas.controller.selection.isEmpty)
    }

    @Test("A stroke has nothing to hand to PaperKit")
    func strokesStay() {
        let rig = Rig()
        let points = (0...5).map { i in
            PKStrokePoint(location: CGPoint(x: 300 + CGFloat(i) * 10, y: 300), timeOffset: TimeInterval(i) * 0.01,
                          size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        var markup = rig.canvas.markup
        markup.subelements.append(PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))))
        rig.canvas.markup = markup
        rig.editor.inkTool.kind = .lasso

        rig.page.selection.select(.rectangle(CGRect(x: 310, y: 290, width: 10, height: 20)))

        #expect(!rig.page.selection.isEmpty)
        #expect(!rig.page.selection.canEditInPaperKit)
    }
}

#endif
