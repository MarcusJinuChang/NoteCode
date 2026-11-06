//
//  ManualClockTests.swift
//  NoteCodeTests
//
//  The clock the debounce tests move by hand, and each debounce's hook (T6):
//  the pause waits on the clock it was given, nothing happens until time
//  passes it, and the hook returns once the work is done. No test here
//  sleeps.
//

#if canImport(UIKit)

import Foundation
import PaperKit
import SwiftData
import Testing
import UIKit
@testable import NoteCode

@Suite("Manual clock", .tags(.pure))
struct ManualClockTests {

    @Test("A sleep wakes once time reaches its deadline, and not before")
    func wakesAtDeadline() async throws {
        let clock = ManualClock()
        let woke = Mutexed(false)
        let sleeper = Task {
            try await clock.sleep(for: .milliseconds(100))
            woke.set(true)
        }
        await clock.untilSleeping()
        clock.advance(by: .milliseconds(99))
        #expect(clock.sleeping == 1)
        #expect(!woke.value)
        clock.advance(by: .milliseconds(1))
        try await sleeper.value
        #expect(woke.value)
        #expect(clock.sleeping == 0)
    }

    @Test("A cancelled sleep throws and stops waiting")
    func cancelled() async {
        let clock = ManualClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(1)) }
        await clock.untilSleeping()
        sleeper.cancel()
        await #expect(throws: CancellationError.self) { try await sleeper.value }
        #expect(clock.sleeping == 0)
    }

    @Test("A deadline already passed returns at once")
    func pastDeadline() async throws {
        let clock = ManualClock()
        clock.advance(by: .seconds(1))
        try await clock.sleep(until: ManualClock.Instant(offset: .milliseconds(500)))
        #expect(clock.sleeping == 0)
    }
}

/// A value two tasks share, for the clock's own tests.
private final class Mutexed<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func set(_ value: Value) { lock.withLock { stored = value } }
}

@Suite("Debounce hooks", .serialized, .tags(.editor))
@MainActor
struct DebounceHookTests {

    @Test("Ink is saved once the pause is over on the scheduler's clock, and settled() waits for the save")
    func inkSave() async throws {
        let container = try ModelContainer(for: NoteSchema.current, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let page = Page()
        container.mainContext.insert(page)
        let clock = ManualClock()
        let saver = DrawingSaveScheduler(page: page, clock: clock, encode: { _ in Data([7]) })

        saver.inkDidChange(PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)))
        await clock.untilSleeping()
        clock.advance(by: .milliseconds(499))
        #expect(saver.isWaiting, "the app's 500ms pause, unchanged")
        #expect(page.drawingData.isEmpty)

        clock.advance(by: .milliseconds(1))
        await saver.settled()
        #expect(!saver.isWaiting)
        #expect(page.drawingData == Data([7]))
    }

    @Test("A toast stays its four seconds on the centre's clock")
    func toast() async {
        let clock = ManualClock()
        let center = ToastCenter(clock: clock)
        center.show("Moved to Recently Deleted")
        await clock.untilSleeping()
        clock.advance(by: .seconds(4) - .milliseconds(1))
        #expect(center.current != nil)
        clock.advance(by: .milliseconds(1))
        await center.settled()
        #expect(center.current == nil)
    }

    @Test("A text size settles after settleDelay on the editor's clock")
    func textSizeSettles() async {
        let harness = EditorHarness("# Title\nsome words\n", wiring: .none, window: CGSize(width: 900, height: 700), area: nil)
        let clock = ManualClock()
        harness.editor.settleClock = clock
        harness.editor.setTextSize(19)
        await clock.untilSleeping()
        clock.advance(by: .milliseconds(119))
        #expect(harness.committedTextSizes.isEmpty, "the app's 120ms pause, unchanged")
        clock.advance(by: .milliseconds(1))
        await harness.editor.sizeSettled()
        #expect(harness.committedTextSizes == [19])
    }

    @Test("Highlighting waits on the coordinator's clock, and highlightingFinished() waits for the paint")
    func highlighting() async {
        let harness = EditorHarness()
        await harness.coordinator.highlightingFinished()
        let clock = ManualClock()
        harness.coordinator.highlightClock = clock

        // Inside the cpp block, so the block is new to the highlighter.
        harness.type("// note\n", at: ("Prose before\n```cpp\n" as NSString).length)
        await clock.untilSleeping()
        clock.advance(by: .milliseconds(19))
        #expect(clock.sleeping == 1, "the app's 20ms pause, unchanged")
        clock.advance(by: .milliseconds(1))
        await harness.coordinator.highlightingFinished()
        #expect(clock.sleeping == 0)
    }
}

#endif
