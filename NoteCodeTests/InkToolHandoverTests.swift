//
//  InkToolHandoverTests.swift
//  NoteCodeTests
//
//  Feedback item 17 (23 Oct): a tool change should show on the Pencil's hover
//  mark at once. The mark is PaperKit's, drawn from the tool it holds, so what
//  the app can promise is that PaperKit holds the new tool before the change
//  returns, with no turn of the run loop in between. These pin that.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Ink tool handover")
@MainActor
struct InkToolHandoverTests {

    @MainActor
    private final class Rig {
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let textView = DocumentTextView.makeConfiguredTextView()
        let canvas = DrawingCanvas(pageSize: CGSize(width: 816, height: 1056))
        let editor = NoteEditor()

        init() {
            textView.frame = window.bounds
            window.addSubview(textView)
            textView.addSubview(canvas)
            window.makeKeyAndVisible()
            editor.attach(textView, canvas: canvas)
            editor.setMode(.ink)
        }
    }

    @Test("PaperKit holds the new tool as soon as the kind changes")
    func kindReachesPaperKitAtOnce() throws {
        let rig = Rig()
        #expect(rig.canvas.tool is PKInkingTool)

        rig.editor.inkTool.kind = .eraser
        #expect(rig.canvas.tool is PKEraserTool)
        rig.editor.inkTool.kind = .lasso
        #expect(rig.canvas.tool is PKLassoTool)
        rig.editor.inkTool.kind = .highlighter
        let marker = try #require(rig.canvas.tool as? PKInkingTool)
        #expect(marker.inkType == .marker)
        // The Pencil's double tap goes through the same property.
        rig.editor.toggleEraser()
        #expect(rig.canvas.tool is PKEraserTool)
        rig.editor.toggleEraser()
        #expect((rig.canvas.tool as? PKInkingTool)?.inkType == .marker)
    }

    @Test("PaperKit holds the new colour and width as soon as they change")
    func colourAndWidthReachPaperKitAtOnce() throws {
        let rig = Rig()
        let settings = InkingSettings(color: InkColor.penShades[1].color, width: .bold)

        rig.editor.inkTool.pen = settings
        let pen = try #require(rig.canvas.tool as? PKInkingTool)
        #expect(pen.width == settings.width.points(for: .pen, ink: .pen))
        #expect(pen.color == settings.color.inkColor)

        rig.editor.inkTool.stepWidth(by: -1)
        let thinner = try #require(rig.canvas.tool as? PKInkingTool)
        #expect(thinner.width < pen.width)
    }
}

#endif
