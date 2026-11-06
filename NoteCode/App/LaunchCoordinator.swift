//
//  LaunchCoordinator.swift
//  NoteCode
//
//  What a launch does once, after the first layout: the list's arrival, the
//  title screen, the Welcome note and the housekeeping.
//

import SwiftData
import SwiftUI

/// The launch's decisions, apart from the view that shows their results.
///
/// `ContentView` waits `SidebarPlan.launchDelay`, then asks this what to do.
/// None of it touches the real store when it failed to open
/// (`storageIsEphemeral`) or a debug launch opened a note of its own
/// (`opensDebugNote`), whose store is in memory and meant to hold exactly
/// that note.
struct LaunchCoordinator {
    var storageIsEphemeral: Bool
    var opensDebugNote: Bool

    /// Whether the list comes in on Home after the delay (or over a note, when
    /// storage failed and the warning is the list's).
    func showsList(noteOpen: Bool) -> Bool {
        SidebarPlan.showsList(noteOpen: noteOpen, storageFailed: storageIsEphemeral)
    }

    /// Whether this launch may make, prune or claim what belongs to the
    /// reader's own store.
    private var mayTouchStore: Bool { !storageIsEphemeral && !opensDebugNote }

    /// Whether the title screen is raised on a first launch, once. The turn
    /// isn't spent when the store failed or a debug launch opened a note.
    func claimsTitleScreen() -> Bool {
        mayTouchStore && WelcomeScreen.claimFirstLaunch()
    }

    /// Gives a first launch its tour. Left in the list rather than opened:
    /// the list is where a new reader should see that there's a list.
    ///
    /// Not when the on-disk store failed: the note would live in memory for
    /// one session, and the flag would say a first launch had happened.
    func makeWelcomeNoteOnFirstLaunch(in context: ModelContext, extensions: AppExtensions) {
        guard mayTouchStore else { return }
        WelcomeNote.makeOnFirstLaunch(in: context, runLines: extensions.runLines)
    }

    /// Forgets the places of notes that are gone, once a launch.
    func pruneNoteMemory(in context: ModelContext) {
        guard mayTouchStore,
              let ids = try? context.fetchIdentifiers(FetchDescriptor<Page>())
        else { return }
        NoteMemory().prune(keeping: Set(ids))
    }

    /// Deletes notes past their 30 days in Recently Deleted, once a launch.
    ///
    /// After the Welcome note's check, not before: a store whose only notes
    /// were deleted has been used, and the Welcome note's check counts them.
    func purgeExpiredNotes(in context: ModelContext) {
        Storage.attempt("purge expired notes") { try Page.purgeExpired(in: context) }
    }
}
