//
//  AppExtensions.swift
//  NoteCode
//

import SwiftUI

/// What an edition adds to the general app.
///
/// `NoteCodeScene` is the whole app with nothing sold in it; an edition's
/// `@main` hands it one of these. The App Store edition's is
/// `AppExtensions.appStore` (Pro/AppStoreEdition.swift), the open-source
/// build's is `.none`. Each member is here because the scene calls it; a
/// later step adds the members its own code reads (docs/refactor/2X-seam.md).
struct AppExtensions: Sendable {
    /// Runs in the scene's `init`, after the device name is set and before
    /// the debug seeding, so whatever it starts reads the launch arguments
    /// first.
    var start: @MainActor @Sendable () -> Void = {}

    /// Wraps the root view, under the model container: where an edition puts
    /// its own objects into the environment.
    var root: @MainActor @Sendable (AnyView) -> AnyView = { $0 }

    /// Under Home's page, where its scroll view ends (the App Store's ad strip).
    var homeFooter: @MainActor @Sendable () -> AnyView = { AnyView(EmptyView()) }

    /// Home is in front of the reader (`ConsentGate`). Called from Home's own
    /// `.task`, not from the footer's view, which a Pro reader never sees.
    var homeAppeared: @MainActor @Sendable () async -> Void = {}

    /// The list foot's first rows, before the general ones (the App Store's:
    /// the ad, then Tip Jar). Only rows that show: an empty one would still
    /// be a blank row. `present` hands the note list a sheet to show.
    var listFootRows: @MainActor @Sendable (_ present: @escaping @MainActor (ExtensionSheet) -> Void) -> [ExtensionRow] = { _ in [] }

    /// The list foot appeared. The App Store's asks the store for tips again
    /// if it had no answer at launch, so a slow store doesn't hide the jar
    /// until the next launch.
    var listFootAppeared: @MainActor @Sendable () -> Void = {}

    /// Rows in Help and About, after Privacy Policy (Ad Privacy Options).
    var aboutRows: @MainActor @Sendable () -> [ExtensionRow] = { [] }

    /// Help and About appeared.
    var settingsAppeared: @MainActor @Sendable () async -> Void = {}

    /// Whether the rating prompt may be asked now. The App Store's waits
    /// while a free reader's tracking prompt is still to come, so the two
    /// system prompts never land on the same Home visit.
    var mayAskForReview: @MainActor @Sendable () -> Bool = { true }

    /// Rows and sections in Settings, each with its place (`SettingsSection`).
    var settingsSections: @MainActor @Sendable () -> [SettingsSection] = { [] }

    /// What the Welcome note and the title screen say Run does.
    var runLines = RunLines.compilerSite

#if DEBUG
    /// Settings keys `-debug-first-launch` clears besides the general ones
    /// (the App Store's: the Run disclosure).
    var debugResetKeys: [String] = []

    /// Wraps the root view in a debug build, outside everything else (the
    /// App Store's: `-debug-paywall`).
    var debugRoot: @MainActor @Sendable (AnyView) -> AnyView = { $0 }
#endif

#if canImport(UIKit)
    /// What each note's editor gains (`EditorFeature`), in the order their
    /// actions are shown. `PageDetailView` installs them in its editor.
    var editorFeatures: [EditorFeatureFactory] = []
#endif

    /// Adds nothing.
    static let none = AppExtensions()
}

/// The sentence about Run in the Welcome note and on the title screen.
nonisolated struct RunLines: Sendable {
    /// In the Welcome note's Code section, after "…start a code block."
    var note: String
    /// The title screen's "Code that runs", after "…for a highlighted block."
    var screen: String

    /// A build with no run service: Run opens the block on a free online
    /// compiler (`CodeDestination`).
    static let compilerSite = RunLines(
        note: "The run button takes it to a free online compiler.",
        screen: "Run takes it to a free online compiler.")
}

/// A row an edition adds to a general list or form.
struct ExtensionRow: Identifiable {
    let id: String
    let view: AnyView

    init(id: String, @ViewBuilder content: () -> some View) {
        self.id = id
        self.view = AnyView(content())
    }
}

/// A sheet an edition's row asks a general view to present.
struct ExtensionSheet: Identifiable {
    let id: String
    let view: AnyView

    init(id: String, @ViewBuilder content: () -> some View) {
        self.id = id
        self.view = AnyView(content())
    }
}

extension EnvironmentValues {
    /// The edition's extensions, for the views that ask for what it adds.
    @Entry var appExtensions = AppExtensions.none
}
