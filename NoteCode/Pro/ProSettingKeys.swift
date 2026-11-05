//
//  ProSettingKeys.swift
//  NoteCode
//
//  The Pro side's settings, as SettingKeys.swift has the rest: the
//  assistant's three, Run's panel width and disclosure, and the ad visit
//  count. Here, not in Settings/, so the open-source build, which has no
//  Pro/, has none of them. The names are pinned by `ProKeysTests`.
//

import Foundation

nonisolated extension SettingKeys {

    /// Settings › Writing › On-Device Assistant (`AIFeatureSettings`). The
    /// length and insert style are stored as their raw text, as every
    /// `@AppStorage` that reads them declares them.
    enum Assistant {
        static let enabled = SettingKey(name: "aiEnabled", defaultValue: true)
        static let answerLength = SettingKey(name: "aiAnswerLength", defaultValue: AIAnswerLength.standard.rawValue)
        static let insertStyle = SettingKey(name: "aiInsertStyle", defaultValue: AIInsertStyle.quote.rawValue)
    }

    /// Run in the app.
    enum Run {
        /// The run panel's width, app-wide (`RunDockWidth`).
        static let panelWidth = SettingKey(name: "runPanelWidth", defaultValue: 360.0)
        /// Whether the reader agreed to `RunDisclosure` before their first run.
        static let disclosureAccepted = SettingKey(name: "runDisclosureAccepted", defaultValue: false)
    }

    /// Ads (`AdConsent`).
    enum Ads {
        /// The number of times Home has appeared, across launches.
        static let homeVisits = SettingKey(name: "adHomeVisits", defaultValue: 0)
    }
}
