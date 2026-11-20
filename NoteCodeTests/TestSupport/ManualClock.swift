//
//  ManualClock.swift
//  NoteCodeTests
//
//  A clock whose time moves only when a test moves it, for the app's
//  debounces (T6): DrawingSaveScheduler, ToastCenter, the highlight delay,
//  NoteEditor's settle, and the views' `debounceClock`. A test hands one in,
//  waits for the debounce to start (`untilSleeping`), moves time past it
//  (`advance(by:)`), and then awaits the work's own hook, never a sleep.
//

import Foundation
import Synchronization

final class ManualClock: Clock, Sendable {

    struct Instant: InstantProtocol {
        /// Time since the clock was made.
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let wake: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextID = 0
        var sleepers: [Int: Sleeper] = [:]
        /// Sleeps cancelled before they had registered.
        var cancelled: Set<Int> = []
        /// Tests waiting for a number of sleepers to register.
        var watchers: [(count: Int, resume: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// How many sleeps are waiting for time to move.
    var sleeping: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (wake: CheckedContinuation<Void, any Error>) in
                enum Outcome { case wait, now, cancelled }
                let (outcome, watchers) = state.withLock { state -> (Outcome, [CheckedContinuation<Void, Never>]) in
                    if state.cancelled.remove(id) != nil { return (.cancelled, []) }
                    if deadline <= state.now { return (.now, []) }
                    state.sleepers[id] = Sleeper(deadline: deadline, wake: wake)
                    return (.wait, Self.dueWatchers(&state))
                }
                switch outcome {
                case .wait: watchers.forEach { $0.resume() }
                case .now: wake.resume()
                case .cancelled: wake.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                if let sleeper = state.sleepers.removeValue(forKey: id) { return sleeper }
                state.cancelled.insert(id)
                return nil
            }
            sleeper?.wake.resume(throwing: CancellationError())
        }
    }

    /// Moves time on by `duration`, and wakes every sleep that is now due.
    func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.value.deadline <= now }
            due.keys.forEach { state.sleepers.removeValue(forKey: $0) }
            return due.values.sorted { $0.deadline < $1.deadline }
        }
        due.forEach { $0.wake.resume() }
    }

    /// Returns once at least `count` sleeps are waiting: once the debounce a
    /// test started has begun its pause, so that `advance(by:)` reaches it.
    /// By suspending, not by polling.
    func untilSleeping(_ count: Int = 1) async {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { state -> Bool in
                if state.sleepers.count >= count { return true }
                state.watchers.append((count, resume))
                return false
            }
            if ready { resume.resume() }
        }
    }

    private static func dueWatchers(_ state: inout State) -> [CheckedContinuation<Void, Never>] {
        let count = state.sleepers.count
        let due = state.watchers.filter { $0.count <= count }.map(\.resume)
        state.watchers.removeAll { $0.count <= count }
        return due
    }
}
