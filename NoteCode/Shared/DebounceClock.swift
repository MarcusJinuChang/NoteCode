import SwiftUI

extension EnvironmentValues {
    /// What the views' own pauses are measured on: the page badge's hold
    /// (`PageDetailView.badgeHold`), the launch delay
    /// (`SidebarPlan.launchDelay`) and the rating prompt's wait in
    /// `ContentView`. Tests set one they move by hand; the app keeps
    /// `ContinuousClock`, which is what `Task.sleep(for:)` uses, so every
    /// pause is as long as it always was.
    @Entry var debounceClock: any Clock<Duration> = ContinuousClock()
}
