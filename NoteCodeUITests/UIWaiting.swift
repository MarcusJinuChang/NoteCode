//
//  UIWaiting.swift
//  NoteCodeUITests
//
//  The two ways a UI test waits, so neither is a bare run-loop spin or
//  sleep (scripts/lint-traps.sh rule 9 counts those here too).
//
//  - `UIWait.until` waits for a condition on the app, and returns as soon
//    as it holds. Use it for anything the test could see arrive: text
//    settling after the keyboard's last keys, a paste landing, a screen
//    that has redrawn.
//  - `UIWait.pace` is a pause on purpose, with its reason named, for the
//    few things a condition can't stand in for: keys typed a beat apart as
//    a reader types them, an animation the app reports no end of, and the
//    time a wrong action is given to show itself before the test says it
//    didn't happen. It is the one sleep the UI tests have, allowed in
//    scripts/lint-allow.txt.
//

import XCTest

enum UIWait {

    /// Waits until `condition` holds or `timeout` passes, and says whether
    /// it held. XCTest evaluates it on the main thread while it waits.
    @MainActor
    @discardableResult
    static func until(timeout: TimeInterval, _ condition: @escaping @MainActor () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
