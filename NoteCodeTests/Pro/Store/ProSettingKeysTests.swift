//
//  ProSettingKeysTests.swift
//  NoteCodeTests
//
//  The Pro key table holds the names and defaults `ProKeysTests` pinned,
//  written out as literals, and the owners' old names forward to it.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Pro setting key table", .tags(.pro))
struct ProSettingKeysTests {

    @Test("Every Pro entry keeps the name and default devices have")
    func tableMatchesThePinnedKeys() {
        #expect(SettingKeys.Assistant.enabled.name == "aiEnabled")
        #expect(SettingKeys.Assistant.enabled.defaultValue == true)
        #expect(SettingKeys.Assistant.answerLength.name == "aiAnswerLength")
        #expect(SettingKeys.Assistant.answerLength.defaultValue == "standard")
        #expect(SettingKeys.Assistant.insertStyle.name == "aiInsertStyle")
        #expect(SettingKeys.Assistant.insertStyle.defaultValue == "quote")
        #expect(SettingKeys.Run.panelWidth.name == "runPanelWidth")
        #expect(SettingKeys.Run.panelWidth.defaultValue == 360.0)
        #expect(SettingKeys.Run.disclosureAccepted.name == "runDisclosureAccepted")
        #expect(SettingKeys.Run.disclosureAccepted.defaultValue == false)
        #expect(SettingKeys.Ads.homeVisits.name == "adHomeVisits")
        #expect(SettingKeys.Ads.homeVisits.defaultValue == 0)
    }

    @Test("The owners' old names forward to the table")
    func oldNamesForward() {
        #expect(AIFeatureSettings.enabledKey == SettingKeys.Assistant.enabled.name)
        #expect(AIFeatureSettings().isEnabled == SettingKeys.Assistant.enabled.defaultValue)
        #expect(RunDockWidth.key == SettingKeys.Run.panelWidth.name)
        #expect(RunDockWidth.initial == SettingKeys.Run.panelWidth.defaultValue)
        #expect(RunDisclosure.key == SettingKeys.Run.disclosureAccepted.name)
    }
}
