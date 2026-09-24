//
//  DrawingSaveScheduler.swift
//  NoteCode
//
//  When a note's ink is written back to its page.
//

import Foundation
import PaperKit
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Writes an open note's ink back to its page: a moment after the reader
/// stops drawing, and straight away when the note closes or the app leaves
/// the screen.
///
/// Only a change to the ink starts a save, never a keystroke (AGENTS.md).
/// Encoding runs off the main actor, so the pause isn't there to hide its
/// cost; it only keeps a burst of strokes from being encoded once each.
///
/// Saves run one at a time, each taking whatever ink is newest when it
/// starts. Two encodes running side by side could finish in either order,
/// and the older ink would land last.
///
/// If the stored ink couldn't be read, nothing is ever written back, and
/// `problem` says so for the page to show.
@MainActor
@Observable
final class DrawingSaveScheduler {

    /// What the reader should be told about this note's ink, if anything.
    private(set) var problem: String?

    @ObservationIgnored private let page: Page
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let encode: @Sendable (PaperMarkup) async throws -> Data

    /// Cleared for good once the stored ink turns out to be unreadable.
    @ObservationIgnored private var mayWrite = true

    /// The newest ink not yet written.
    @ObservationIgnored private var pending: PaperMarkup?

    /// The pause after the last change.
    @ObservationIgnored private var waiting: Task<Void, Never>?

    /// The save running now, or the last one to run.
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    /// - Parameters:
    ///   - delay: how long drawing has to pause before a save.
    ///   - encode: for tests; the app always uses `DrawingCodec.encode`.
    init(
        page: Page,
        delay: Duration = .milliseconds(500),
        encode: @escaping @Sendable (PaperMarkup) async throws -> Data = DrawingCodec.encode
    ) {
        self.page = page
        self.delay = delay
        self.encode = encode
    }

    /// The page's stored ink, in print coordinates, or `nil` for none.
    ///
    /// Unreadable ink comes back as `nil` too, and turns saving off for this
    /// note: whatever is drawn now would otherwise be written over it.
    func loadInk() -> PaperMarkup? {
        switch DrawingCodec.decode(page.drawingData) {
        case .none:
            return nil
        case .ink(let markup):
            return markup
        case .unreadable(let reason):
            mayWrite = false
            problem = reason + " It's been left as it is, and ink drawn on this note won't be saved."
            return nil
        }
    }

    /// Takes the note's ink after the reader changed it, and saves it once
    /// drawing pauses.
    func inkDidChange(_ markup: PaperMarkup) {
        guard mayWrite else { return }
        pending = markup
        waiting?.cancel()
        waiting = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.waiting = nil
            await self.startSave().value
        }
    }

    /// Saves anything not yet saved, without waiting for the pause, and
    /// returns once it's on the page.
    func flush() async {
        waiting?.cancel()
        waiting = nil
        await startSave().value
    }

    /// Whether ink is waiting for the pause to end. For tests.
    var isWaiting: Bool { waiting != nil }

    private func startSave() -> Task<Void, Never> {
        let previous = lastSave
        let save = Task { [weak self] in
            await previous?.value
            await self?.writePending()
        }
        lastSave = save
        return save
    }

    private func writePending() async {
        guard mayWrite, let markup = pending else { return }
        pending = nil

        let data: Data
        do {
            data = try await encode(markup)
        } catch {
            // Keep it for the next save, unless newer ink arrived meanwhile.
            if pending == nil {
                pending = markup
            }
            problem = "Ink couldn't be saved: \(error.localizedDescription)"
            return
        }

        // Deleted while the encode ran: there's no note left to save to.
        // `isDeleted` alone misses it once the deletion is saved — it reads
        // false again then, as in Core Data, and the page loses its context.
        // Never read the ink back from a page in that state: SwiftData traps.
        guard page.modelContext != nil, !page.isDeleted else { return }
        page.drawingData = data
        // Or a note only drawn on would sink down the list.
        page.modifiedAt = .now
        problem = nil
    }
}

#if canImport(UIKit)

extension DrawingSaveScheduler {

    /// Saves now, with time from UIKit to finish, then runs `commit`.
    ///
    /// For when the app leaves the screen. A suspended app finishes nothing,
    /// and one swiped away in the app switcher never reaches the background
    /// at all, so this is asked for as soon as the scene stops being active.
    func flushBeforeSuspending(then commit: @escaping @MainActor () -> Void) {
        let lease = BackgroundTimeLease(name: "Save ink")
        Task {
            await flush()
            commit()
            lease.end()
        }
    }
}

/// Time UIKit grants to finish work after the app leaves the screen, ended
/// exactly once — by the work finishing, or by the time running out.
@MainActor
private final class BackgroundTimeLease {

    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

#endif
