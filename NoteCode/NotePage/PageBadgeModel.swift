//
//  PageBadgeModel.swift
//  NoteCode
//
//  The page badge's state: where the reader is while the note scrolls,
//  shown until a second after the scrolling stops. It was three `@State`s
//  and a timer in `PageDetailView`.
//

#if canImport(UIKit)
import SwiftUI

@MainActor
@Observable
final class PageBadgeModel {
    /// Where the reader is, as the badge shows it.
    private(set) var place: NoteMemory.Place?
    private(set) var isVisible = false
    @ObservationIgnored private var timer: Task<Void, Never>?

    /// It comes in quickly, so it answers the scroll that showed it.
    static let fadeIn: TimeInterval = 0.15
    /// How long it stays after the last movement.
    static let hold: Duration = .seconds(1)
    /// It goes more slowly than it came.
    static let fadeOut: TimeInterval = 0.3

    /// The note scrolled: the badge shows the page, and goes a second after
    /// the last movement, measured on `clock` (`EnvironmentValues.debounceClock`).
    func noteScrolled(to place: NoteMemory.Place, clock: any Clock<Duration>) {
        if self.place != place { self.place = place }
        if !isVisible {
            withAnimation(.easeOut(duration: Self.fadeIn)) { isVisible = true }
        }
        timer?.cancel()
        timer = Task { [weak self] in
            try? await clock.sleep(for: Self.hold)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Self.fadeOut)) { self?.isVisible = false }
        }
    }
}
#endif
