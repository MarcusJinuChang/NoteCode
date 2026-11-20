//
//  TestDefaults.swift
//  NoteCodeTests
//
//  A test that sets `UserDefaults.standard` sets the simulator app's own
//  settings, which the next test, and the next launch, then read. A test gets
//  a `UserDefaults` of its own instead and passes it to whatever reads
//  settings: a `defaults:` parameter, or `.defaultAppStorage(_:)` over a
//  hosted view.
//

import Foundation

/// A `UserDefaults` with a name no other test has, removed when this goes.
///
///     let store = TestDefaults()
///     store.defaults.set("dark", forKey: SettingKeys.General.appearance.name)
///
/// Keep it as long as the test needs the settings: a stored property of a
/// suite (each test makes a new one) or of the rig the test builds. The
/// domain is removed when the last reference goes, or at once by `remove()`.
final class TestDefaults {

    let defaults: UserDefaults
    let suiteName: String

    /// `label` is only there to tell the leftovers apart in the simulator's
    /// preferences if a run is killed before the domain is removed.
    init(_ label: String = "Test") {
        suiteName = "NoteCodeTests.\(label).\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        remove()
    }

    /// Empties the domain. Reads and writes after this start from nothing.
    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
