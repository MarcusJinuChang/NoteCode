//
//  SettingsSection.swift
//  NoteCode
//
//  What an edition adds to Settings (`AppExtensions.settingsSections`), and
//  where it goes.
//

import SwiftUI

/// A row or section an edition adds to Settings.
struct SettingsSection: Identifiable {
    enum Placement {
        /// A row in Settings' list, after General (the App Store's: Pro).
        case afterGeneral
        /// A section at the end of Writing's form (the App Store's: the
        /// on-device assistant).
        case writing
    }

    let id: String
    let placement: Placement
    let view: AnyView

    init(id: String, placement: Placement, @ViewBuilder content: () -> some View) {
        self.id = id
        self.placement = placement
        self.view = AnyView(content())
    }
}

extension AppExtensions {
    /// The edition's rows or sections for one place in Settings, in its order.
    @MainActor
    func settings(at placement: SettingsSection.Placement) -> [SettingsSection] {
        settingsSections().filter { $0.placement == placement }
    }
}
