//
//  OverlayViewportTests.swift
//  NoteCodeTests
//
//  T5, before 2T5: `CodeBlockOverlay` as a reader meets it today. Every code
//  block has a bar, but only a block TextKit has laid out in its viewport
//  shows one; a block scrolled away keeps its bar, hidden. Bars follow their
//  blocks through edits, and go with them. `PageOverlayTests` covers bars on
//  opening, for a block just typed, under the canvas and at the panel's edge.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Action bars and the viewport", .tags(.layout))
@MainActor
struct OverlayViewportTests {

    /// A block at the top and another a few thousand points further down.
    nonisolated private static let note = "Near the top\n```cpp\nint first = 1;\n```\n"
        + TestFixtures.longProse + "\n" + TestFixtures.longProse
        + "\n```python\nprint(2)\n```\nThe end.\n"

    private func open(_ text: String = Self.note) -> EditorHarness {
        EditorHarness(text, area: CGSize(width: 872, height: 1200))
    }

    /// Every bar in the text view, shown or not.
    private func bars(in harness: EditorHarness) -> [CodeBlockActionBar] {
        harness.textView.subviews.compactMap { $0 as? CodeBlockActionBar }
    }

    private func shown(in harness: EditorHarness) -> [CodeBlockActionBar] {
        bars(in: harness).filter { !$0.isHidden }
    }

    /// Scrolls the text view, which owns scrolling, and lets it lay out.
    private func scroll(_ harness: EditorHarness, toShow text: String) {
        let line = harness.rect(of: text)
        harness.textView.contentOffset = CGPoint(x: 0, y: max(0, line.minY - 200))
        harness.layOut()
    }

    /// Deletes `text` the way the keyboard does: a selection, then delete.
    private func delete(_ text: String, in harness: EditorHarness) {
        harness.textView.selectedRange = harness.source.range(of: text)
        harness.textView.deleteBackward()
        harness.coordinator.textViewDidChange(harness.textView)
        harness.layOut()
    }

    @Test("Every block has a bar; only the one in the viewport is shown")
    func oneBarPerBlock() throws {
        let harness = open()

        #expect(bars(in: harness).count == 2)
        let shown = shown(in: harness)
        try #require(shown.count == 1)
        let top = harness.rect(of: "```cpp")
        #expect(abs(shown[0].frame.midY - top.midY) < top.height, "the shown bar is the first block's")
        #expect(harness.visibleBars.count == 1)
    }

    @Test("Scrolled to the far block, its bar shows and the first block's is hidden")
    func scrolledAway() throws {
        let harness = open()
        scroll(harness, toShow: "print(2)")

        let shown = shown(in: harness)
        try #require(shown.count == 1)
        let far = harness.rect(of: "```python")
        #expect(abs(shown[0].frame.midY - far.midY) < far.height, "the shown bar is the far block's")
        #expect(harness.visibleBars.count == 1)

        scroll(harness, toShow: "Near the top")
        let back = self.shown(in: harness)
        try #require(back.count == 1)
        let top = harness.rect(of: "```cpp")
        #expect(abs(back[0].frame.midY - top.midY) < top.height)
    }

    @Test("Lines typed above a block move its bar down with it")
    func barFollowsItsBlock() throws {
        let harness = open()
        let before = try #require(shown(in: harness).first).frame
        let fenceBefore = harness.rect(of: "```cpp")

        harness.type("One more line\nAnd another\n", at: 0)

        let after = try #require(shown(in: harness).first).frame
        let fenceAfter = harness.rect(of: "```cpp")
        #expect(fenceAfter.minY > fenceBefore.minY)
        #expect(abs((after.minY - before.minY) - (fenceAfter.minY - fenceBefore.minY)) < 1)
    }

    @Test("Deleting a block takes its bar away; the other block keeps its own")
    func deletedBlockLosesItsBar() throws {
        let harness = open()

        delete("```cpp\nint first = 1;\n```\n", in: harness)

        #expect(bars(in: harness).count == 1)
        // The first block's bar was the one on screen; the one left is the
        // far block's, which is still out of the viewport.
        #expect(shown(in: harness).isEmpty)
        scroll(harness, toShow: "print(2)")
        #expect(shown(in: harness).count == 1)
    }

    @Test("A note with no code has no bars")
    func noCodeNoBars() {
        let harness = open("Just prose.\nNothing fenced.\n")

        #expect(bars(in: harness).isEmpty)
    }
}

#endif
