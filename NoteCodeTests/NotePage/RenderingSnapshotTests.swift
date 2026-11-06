//
//  RenderingSnapshotTests.swift
//  NoteCodeTests
//
//  T10 (docs/refactor/T-tests.md): five things a geometry test passes while
//  looking wrong, checked against a reference image with a tolerance
//  (`Snapshot`). Each is drawn small, so a run takes a second or two.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Rendering snapshots", .tags(.layout))
@MainActor
struct RenderingSnapshotTests {

    private static let area = CGSize(width: 640, height: 360)

    /// A page of `text`, as the app wires it, markers hidden away from the caret.
    private func editor(_ text: String, caretMarker: String? = nil, layout: PageLayout = PageLayout(),
                        area: CGSize = RenderingSnapshotTests.area) -> EditorHarness {
        EditorHarness(text, caretMarker: caretMarker, layout: layout, rendersMarkdown: true,
                      window: area, area: nil)
    }

    @Test("A code block is a panel with its language colours")
    func codePanel() async throws {
        let harness = editor("Prose before\n```cpp\nint value = query(gap);\nfor (int i = 0; i < n; i++) {}\n```\nProse after the block\n|",
                             caretMarker: "|")
        try await harness.settle()
        Snapshot.verify(harness.window, region: harness.window.bounds, named: "codePanel")
    }

    @Test("Markdown marks are hidden away from the caret")
    func hiddenMarkers() async throws {
        let note = "# A heading\n**bold** and *italic* and `code` and ~~gone~~\n- one\n- two\n- [ ] a task\n> a quote\nThe caret line, **bold** here|\n"
        let harness = editor(note, caretMarker: "|")
        try await harness.settle()
        Snapshot.verify(harness.window, region: harness.window.bounds, named: "hiddenMarkers")
    }

    @Test("A display formula is drawn centred and its source takes no room")
    func displayFormula() async throws {
        let harness = editor("Before the block.\n$$\n\\sum_{i=1}^{n} \\frac{i}{2}\n$$\nAfter it, with $x^2$ inline.\n|", caretMarker: "|")
        try await harness.settle()
        Snapshot.verify(harness.window, region: harness.window.bounds, named: "displayFormula")
    }

    @Test("Print layout shows the sheet, its margins and the gap to the next")
    func printLayout() async throws {
        let layout = PageLayout(orientation: .portrait, mode: .print)
        let harness = editor(String(repeating: TestFixtures.longProse + "\n", count: 3) + "|", caretMarker: "|", layout: layout, area: CGSize(width: 900, height: 700))
        try await harness.settle()
        harness.textView.contentOffset.y = layout.sheet(ofPage: 0).maxY - 350
        harness.layOut()
        Snapshot.verify(harness.window, region: harness.window.bounds, named: "printLayout")
    }

    @Test("Ink that crosses a page break is drawn on both sheets")
    func inkAcrossPageBreak() async throws {
        let layout = PageLayout(orientation: .portrait, mode: .print)
        let harness = PageHarness(text: TestFixtures.severalPages, area: CGSize(width: 900, height: 700), layout: layout)
        // The reference is light. This window is in the test host's scene, so
        // it would otherwise follow the simulator's appearance.
        harness.window.overrideUserInterfaceStyle = .light
        // From the end of the first sheet's body to the start of the second's.
        let from = layout.bodyTop(ofPage: 0) + layout.bodyHeight - 60
        let to = layout.bodyTop(ofPage: 1) + 60
        let edge = layout.bodyTop(ofPage: 0) + layout.bodyHeight
        let points = (0..<40).map { i in
            PKStrokePoint(location: CGPoint(x: 300 + CGFloat(i) * 6, y: from + (to - from) * CGFloat(i) / 39),
                          timeOffset: Double(i) * 0.01, size: CGSize(width: 6, height: 6),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .systemRed), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)))
        harness.setInk(PKDrawing(strokes: [stroke]))
        harness.page.textView.contentOffset.y = edge - 350
        harness.layOut()
        // PaperKit draws the second sheet's ink in tiles, off the main thread,
        // with nothing to await; and a snapshot taken before they land keeps
        // the gap. So this one test waits (lint-traps rule 9 counts it).
        try await Task.sleep(for: .milliseconds(500))
        harness.layOut()
        let region = CGRect(x: 0, y: 0, width: 900, height: 700)
        Snapshot.verify(harness.window, region: region, named: "inkAcrossPageBreak")
    }
}

#endif
