//
//  UIWaiting.swift
//  NoteCodeUITests
//
//  The two ways a UI test waits, so neither is a bare run-loop spin or
//  sleep (scripts/lint-traps.sh rule 9 counts those here too).
//
//  - `UIWait.until` waits for a condition on the app (an `XCTWaiter` on an
//    expectation a timer fulfils), and returns as soon as it holds. Use it
//    for anything the test could see arrive: text settling after the
//    keyboard's last keys, a paste landing, a screen that has redrawn.
//  - `UIWait.pace` is a pause on purpose, with its reason named, for the
//    few things a condition can't stand in for: keys typed a beat apart as
//    a reader types them, an animation the app reports no end of, and the
//    time a wrong action is given to show itself before the test says it
//    didn't happen. Its one sleep is allowed in scripts/lint-allow.txt,
//    and rule 9 counts every call of it, so each caller is listed there
//    with its reason too.
//

import XCTest

enum UIWait {

    /// Waits until `condition` holds or `timeout` passes, and says whether
    /// it held. It is checked every `interval` on the main run loop, which
    /// `XCTWaiter` turns while it waits; an `XCTNSPredicateExpectation`
    /// with no object to observe checks only about once a second, so each
    /// Undo or screenshot it waited for cost up to a second.
    @MainActor
    @discardableResult
    static func until(
        timeout: TimeInterval,
        every interval: TimeInterval = 0.05,
        _ condition: @escaping @MainActor () -> Bool
    ) -> Bool {
        if condition() { return true }
        let held = XCTestExpectation(description: "condition held")
        let check = Timer(timeInterval: interval, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard condition() else { return }
                timer.invalidate()
                held.fulfill()
            }
        }
        RunLoop.main.add(check, forMode: .common)
        defer { check.invalidate() }
        return XCTWaiter.wait(for: [held], timeout: timeout) == .completed
    }

    /// Why a test pauses rather than waits for something.
    enum Pace {
        /// Keys a beat apart, as a reader types them: the bug being tested
        /// needs each key to land on its own.
        case readerTyping
        /// An animation that reports no end: the test acts once it is over.
        case animation
        /// A touch that must do nothing is given time to do something
        /// before the test checks that it didn't.
        case nothingHappens
    }

    /// Pauses for `seconds`, on purpose, for `reason`.
    static func pace(_ seconds: TimeInterval, _ reason: Pace) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
