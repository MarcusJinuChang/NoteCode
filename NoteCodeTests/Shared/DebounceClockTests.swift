//
//  DebounceClockTests.swift
//  NoteCodeTests
//
//  The environment's clock reads as unchanged between passes, or every view
//  that reads it builds its body again on each one (the iPhone sheet freeze,
//  PR #234).
//

import SwiftUI
import Testing
@testable import NoteCode

@Suite("Debounce clock", .tags(.pure))
struct DebounceClockTests {

    @Test("The default is one instance, equal on every read")
    func defaultIsStable() {
        let first = EnvironmentValues().debounceClock
        let second = EnvironmentValues().debounceClock
        #expect(first === second)
        #expect(first == second)
    }

    @Test("A test's own clock reads as a change")
    func otherClockDiffers() {
        let manual = DebounceClock(ManualClock())
        #expect(manual != EnvironmentValues().debounceClock)
        #expect(manual == manual)
    }

    @Test("Sleeping waits on the clock it holds")
    func sleepUsesHeldClock() async throws {
        let manual = ManualClock()
        let clock = DebounceClock(manual)
        let slept = Task { try await clock.sleep(for: .seconds(5)) }
        await manual.untilSleeping()
        manual.advance(by: .seconds(5))
        try await slept.value
    }
}
