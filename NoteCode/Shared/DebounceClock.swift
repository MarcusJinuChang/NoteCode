import SwiftUI

/// The clock the views' own pauses are measured on, as an environment value
/// SwiftUI can compare.
///
/// The environment held a bare `any Clock<Duration>` until 7 Nov. SwiftUI
/// cannot compare an existential, so it read as changed on every pass, and
/// every view that reads it (`PageDetailView`, `ContentView`) built its body
/// again each time. On iPhone width a sheet over a note then never finished
/// laying out: the body ran inside the sheet's layout, which asked for layout
/// again, and the app froze (PR #234, together with an `OpenNote` rebuilt
/// on every build). A class compared by identity is the
/// same value on every pass, so nothing reads as changed unless a test puts a
/// different clock in.
nonisolated final class DebounceClock: Equatable, Sendable {
    let clock: any Clock<Duration>

    init(_ clock: any Clock<Duration>) {
        self.clock = clock
    }

    /// The app's one clock: `ContinuousClock`, which is what
    /// `Task.sleep(for:)` uses, so every pause is as long as it always was.
    static let continuous = DebounceClock(ContinuousClock())

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }

    static func == (lhs: DebounceClock, rhs: DebounceClock) -> Bool {
        lhs === rhs
    }
}

extension EnvironmentValues {
    /// What the views' own pauses are measured on: the page badge's hold
    /// (`PageBadgeModel.hold`), the edit date's pause
    /// (`ModifiedAtBatcher.pause`), the launch delay
    /// (`SidebarPlan.launchDelay`) and the rating prompt's wait in
    /// `ContentView`. Tests set one they move by hand.
    @Entry var debounceClock: DebounceClock = .continuous
}
