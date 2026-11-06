//
//  HighlightingDebounceTests.swift
//  NoteCodeTests
//
//  T5, before 2T1: what a reader sees of syntax colouring around an edit,
//  as it is today. An edit restyles at once and leaves the block it changed
//  plain; the colours come after a short pause, and an edit made before they
//  land replaces the pass in flight, so only colours for the text as it now
//  is are ever painted. Each test awaits `highlightingFinished()`, never a
//  sleep.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Highlighting after an edit", .tags(.editor))
@MainActor
struct HighlightingDebounceTests {

    nonisolated private static let note = "Notes\n```cpp\nint value = 1;\n```\nAfter the block.\n"

    /// A note open and coloured, as it is once the reader starts typing.
    private func openNote(_ text: String = Self.note) async -> EditorHarness {
        let harness = EditorHarness(text, style: .light)
        // The harness's first restyle runs before its window's appearance is
        // applied, and a change of appearance forgets what was highlighted:
        // restyle once more so what is remembered is as it is in the app.
        harness.coordinator.restyle(harness.textView)
        await harness.coordinator.highlightingFinished()
        return harness
    }

    private func colour(at offset: Int, in harness: EditorHarness) -> UIColor? {
        harness.textView.textStorage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor
    }

    /// Characters in `range` drawn in anything but the text colour.
    private func coloured(in range: NSRange, of harness: EditorHarness) -> [Int] {
        (range.location..<NSMaxRange(range)).filter { offset in
            let colour = colour(at: offset, in: harness)
            return colour != nil && colour != UIColor.label
        }
    }

    @Test("A note's code is coloured once the pass after opening has landed")
    func colouredOnOpen() async {
        let harness = await openNote()

        #expect(colour(at: harness.offset(of: "int value"), in: harness) != UIColor.label)
    }

    @Test("What an edit types is plain until the pause is over; the rest of its block keeps its colours")
    func coloursLandAfterThePause() async {
        let harness = await openNote()

        harness.type("return 2;\n", at: harness.offset(of: "int value"))
        // The debounce: the restyle the edit made is synchronous, the
        // colouring is not, so what was typed is plain now and coloured once
        // the pass has landed (below). How long the pause is (20ms) is pinned
        // below, on T6's injected clock.
        #expect(colour(at: harness.offset(of: "return"), in: harness) == UIColor.label)
        // The rest of the block keeps the colours it had, though
        // `scheduleHighlighting`'s comment says the restyle resets every
        // foreground in it to `.label`. Pinned as found, not a decision: 2T1
        // keeps the code's behaviour and doesn't make the code match its
        // comment; changing either is an F fix.
        #expect(colour(at: harness.offset(of: "int value"), in: harness) != UIColor.label)

        await harness.coordinator.highlightingFinished()
        #expect(colour(at: harness.offset(of: "return"), in: harness) != UIColor.label)
        #expect(colour(at: harness.offset(of: "int value"), in: harness) != UIColor.label)
    }

    @Test("An edit made before the colours land replaces the pass: colours land where the text is now")
    func newerEditReplacesThePass() async {
        let harness = await openNote()

        // The first pass would colour `int` at its offset now ...
        harness.type("int a = 1;\n", at: harness.offset(of: "int value"))
        // ... and this moves everything after it further than that offset, so
        // a pass painting the old offsets would colour this prose.
        let prose = "Some prose typed first, longer than the fence line\n"
        harness.type(prose, at: 0)

        await harness.coordinator.highlightingFinished()
        let typed = NSRange(location: 0, length: (prose as NSString).length)
        #expect(coloured(in: typed, of: harness).isEmpty)
        #expect(colour(at: harness.offset(of: "int a"), in: harness) != UIColor.label)
        #expect(colour(at: harness.offset(of: "int value"), in: harness) != UIColor.label)
    }

    @Test("An edit outside the code keeps the colours already there, with no pass to wait for")
    func proseEditKeepsColours() async {
        let harness = await openNote()

        harness.type("More prose. ", at: harness.offset(of: "After the block."))
        #expect(colour(at: harness.offset(of: "int value"), in: harness) != UIColor.label)
        #expect(coloured(in: NSRange(location: 0, length: 5), of: harness).isEmpty, "Notes stays plain")
    }

    @Test("Prose is never coloured, before the pass or after it")
    func proseStaysPlain() async {
        let harness = await openNote()

        harness.type("int x;\n", at: harness.offset(of: "int value"))
        #expect(coloured(in: harness.source.range(of: "After the block."), of: harness).isEmpty)
        await harness.coordinator.highlightingFinished()
        #expect(coloured(in: harness.source.range(of: "After the block."), of: harness).isEmpty)
    }

    // MARK: On T6's clock

    @Test("Colours land when the 20ms pause is over, not a millisecond before")
    func coloursLandAtTwentyMilliseconds() async {
        let harness = await openNote()
        let clock = ManualClock()
        harness.coordinator.highlightClock = clock

        harness.type("return 2;\n", at: harness.offset(of: "int value"))
        await clock.untilSleeping()
        clock.advance(by: .milliseconds(19))
        #expect(clock.sleeping == 1, "still inside the pause")
        #expect(colour(at: harness.offset(of: "return"), in: harness) == UIColor.label)

        clock.advance(by: .milliseconds(1))
        await harness.coordinator.highlightingFinished()
        #expect(clock.sleeping == 0)
        #expect(colour(at: harness.offset(of: "return"), in: harness) != UIColor.label)
    }

    @Test("A newer edit cancels the pause of the older pass: one pause is left, and it is the newer one's")
    func newerEditCancelsTheOlderPause() async {
        let harness = await openNote()
        let clock = ManualClock()
        harness.coordinator.highlightClock = clock

        harness.type("int a = 1;\n", at: harness.offset(of: "int value"))
        await clock.untilSleeping()
        clock.advance(by: .milliseconds(15))

        // 15ms in, a second edit: the older pass must not land at 20ms.
        let prose = "Some prose typed first, longer than the fence line\n"
        harness.type(prose, at: 0)
        await clock.untilSleeping()
        #expect(clock.sleeping == 1, "the older pause was cancelled, not left running")

        // 20ms after the first edit is only 5ms after the second.
        clock.advance(by: .milliseconds(5))
        #expect(clock.sleeping == 1, "the newer pass still has 15ms to wait")
        #expect(colour(at: harness.offset(of: "int a"), in: harness) == UIColor.label)

        clock.advance(by: .milliseconds(15))
        await harness.coordinator.highlightingFinished()
        #expect(clock.sleeping == 0)
        #expect(colour(at: harness.offset(of: "int a"), in: harness) != UIColor.label)
        let typed = NSRange(location: 0, length: (prose as NSString).length)
        #expect(coloured(in: typed, of: harness).isEmpty)
    }
}

#endif
