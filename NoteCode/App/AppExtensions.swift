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

#if canImport(UIKit)
    /// What each note's editor gains (`EditorFeature`), in the order their
    /// actions are shown. `PageDetailView` installs them in its editor.
    var editorFeatures: [EditorFeatureFactory] = []
#endif

    /// Adds nothing.
    static let none = AppExtensions()
}

extension EnvironmentValues {
    /// The edition's extensions, for the views that ask for what it adds.
    @Entry var appExtensions = AppExtensions.none
}
