//
//  TextRegionSelectionTests.swift
//  NoteCodeTests
//
//  Step 4 of docs/design/object-system.md: text under the Select tool's shape,
//  and recolouring it with the ink.
//

#if canImport(UIKit)

import Foundation
import PaperKit
import PencilKit
import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Select tool and text")
@MainActor
struct TextRegionSelectionTests {

    /// Ten points to a character, a line twenty high, offsets from `base`.
    private static func line(_ base: Int, _ count: Int, y: CGFloat, x: CGFloat = 0) -> TextRegion.Line {
        TextRegion.Line(
            range: NSRange(location: base, length: count),
            rect: CGRect(x: x, y: y, width: CGFloat(count) * 10, height: 20),
            offset: { px in base + max(0, min(count, Int(((px - x) / 10).rounded()))) }
        )
    }

    // MARK: Geometry

    @Test("A rectangle covers the characters inside it on each line it crosses")
    func rectangleColumn() {
        let lines = [Self.line(0, 20, y: 0), Self.line(21, 20, y: 20), Self.line(42, 20, y: 40)]

        let pieces = TextRegion.pieces(for: .rectangle(CGRect(x: 50, y: 5, width: 60, height: 50)), lines: lines)

        #expect(pieces.map(\.range) == [NSRange(location: 5, length: 6), NSRange(location: 26, length: 6), NSRange(location: 47, length: 6)])
        #expect(pieces[0].rect.minX == 50 && pieces[0].rect.width == 60)
    }

    @Test("A rectangle that misses a line, or only taps it, gives nothing")
    func missesAndTaps() {
        let lines = [Self.line(0, 20, y: 0), Self.line(21, 20, y: 100)]

        #expect(TextRegion.pieces(for: .rectangle(CGRect(x: 0, y: 40, width: 200, height: 20)), lines: lines).isEmpty)
        #expect(TextRegion.pieces(for: .rectangle(CGRect(x: 50, y: 5, width: 0.2, height: 8)), lines: lines).isEmpty)
        #expect(TextRegion.pieces(for: .rectangle(CGRect(x: 500, y: 0, width: 50, height: 20)), lines: lines).isEmpty, "past the line's end")
    }

    @Test("A lasso covers each line from where it first crosses the line's middle to where it last does")
    func lassoSpan() {
        let lines = [Self.line(0, 30, y: 0), Self.line(31, 30, y: 20)]
        let triangle = SelectionShape.lasso([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 0, y: 40)])

        let pieces = TextRegion.pieces(for: triangle, lines: lines)

        // At y 10 the triangle spans x 0...150; at y 30, 0...50.
        #expect(pieces.map(\.range) == [NSRange(location: 0, length: 15), NSRange(location: 31, length: 5)])
    }

    @Test("An ink colour stands for the nearest text colour, and a grey for none")
    func colourMapping() {
        for colour in TextColour.allCases {
            let r = Double((colour.hex >> 16) & 0xFF) / 255, g = Double((colour.hex >> 8) & 0xFF) / 255, b = Double(colour.hex & 0xFF) / 255
            #expect(TextColour.nearest(red: r, green: g, blue: b) == colour)
        }
        #expect(TextColour.nearest(red: 1, green: 0.1, blue: 0.1) == .red)
        #expect(TextColour.nearest(red: 0.1, green: 0.3, blue: 1) == .blue)
        #expect(TextColour.nearest(red: 0, green: 0, blue: 0) == nil)
        #expect(TextColour.nearest(red: 1, green: 1, blue: 1) == nil)
        #expect(TextColour.nearest(red: 0.5, green: 0.52, blue: 0.5) == nil)
    }

    // MARK: On a real page

    @MainActor
    private final class Rig {
        let window = makeSceneLessTestWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
        let textView = DocumentTextView.makeConfiguredTextView()
        let editor = NoteEditor()
        let page: PageView
        /// The text view's delegate, as in the app: it turns away the keyboard's
        /// smart punctuation during an edit the app makes, which otherwise
        /// curls a colour tag's quotes whenever other tests have left a scene
        /// active.
        private let coordinator: DocumentTextView.Coordinator
        var selection: InkSelection { page.selection }

        init(_ text: String, locked: Bool = false) {
            let box = PageSettlingTests.Box()
            coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
            coordinator.editor = editor
            textView.delegate = coordinator
            textView.text = text
            page = PageView(textView: textView)
            page.frame = window.bounds
            window.addSubview(page)
            window.makeKeyAndVisible()
            page.layoutIfNeeded()
            editor.attach(textView, canvas: page.canvas, page: page)
            if locked { editor.setTextLocked(true) }
            editor.setMode(.ink)
            textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
            page.layoutIfNeeded()
        }

        var lines: [TextRegion.Line] { TextRegion.visibleLines(in: textView) }

        /// Lays the text out again after an edit; the app does it every frame.
        func relayout() {
            page.layoutIfNeeded()
            textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
            page.layoutIfNeeded()
        }
    }

    @Test("The lines read from a text view cover its text, left to right, top to bottom")
    func readsLines() throws {
        let rig = Rig("alpha beta gamma\ndelta epsilon")
        let lines = rig.lines

        #expect(lines.count >= 2)
        #expect(lines[0].range.location == 0)
        #expect(lines[0].range.length >= 16)
        #expect(lines[0].rect.maxY <= lines[1].rect.minY + 1)
        let from = lines[0].offset(lines[0].rect.minX)
        let to = lines[0].offset(lines[0].rect.maxX)
        #expect(from == 0)
        #expect(to >= 15)
    }

    @Test("Recolouring a selection that covers text colours the text, and one undo takes it back")
    func recoloursText() throws {
        let rig = Rig("alpha beta gamma\ndelta epsilon")
        let first = try #require(rig.lines.first)
        rig.editor.inkTool.kind = .lasso

        #expect(rig.selection.select(.rectangle(first.rect.insetBy(dx: -2, dy: 0))))
        #expect(rig.selection.textPieces.count == 1)
        #expect(!rig.selection.hasInk)

        rig.selection.recolour(to: .red)

        #expect(rig.textView.text.contains("color:#E5484D"))
        #expect(rig.textView.text.contains("alpha beta gamma"))
        #expect(rig.textView.text.hasSuffix("delta epsilon"), "the line below is untouched")

        rig.textView.undoManager?.undo()
        #expect(rig.textView.text == "alpha beta gamma\ndelta epsilon")
    }

    @Test("A grey takes the colour off")
    func greyTakesItOff() throws {
        let rig = Rig("alpha beta")
        let first = try #require(rig.lines.first)
        rig.editor.inkTool.kind = .lasso
        rig.selection.select(.rectangle(first.rect))
        rig.selection.recolour(to: .red)
        #expect(rig.textView.text.contains("color:"))
        rig.relayout()

        // The line as it is now: this rig doesn't hide markers, so it is
        // longer than it was.
        let again = try #require(rig.lines.first)
        rig.selection.select(.rectangle(again.rect))
        rig.selection.recolour(to: .black)

        #expect(!rig.textView.text.contains("color:"))
    }

    @Test("Code is never selected as text, and a locked note's text isn't either")
    func codeAndLocked() throws {
        let rig = Rig("prose line\n```cpp\nint x;\n```\n")
        rig.editor.inkTool.kind = .lasso
        // The coordinator that supplies code ranges isn't in this rig; say where code is.
        rig.editor.codeRanges = { [CodeRange(range: NSRange(location: 11, length: 17), isClosed: true)] }
        let lines = rig.lines
        let code = try #require(lines.first { $0.range.location >= 11 })

        rig.selection.select(.rectangle(code.rect))
        #expect(rig.selection.textPieces.isEmpty)

        let locked = Rig("alpha beta", locked: true)
        locked.editor.inkTool.kind = .lasso
        let line = try #require(locked.lines.first)
        locked.selection.select(.rectangle(line.rect))
        #expect(locked.selection.textPieces.isEmpty)
    }
}

#endif
