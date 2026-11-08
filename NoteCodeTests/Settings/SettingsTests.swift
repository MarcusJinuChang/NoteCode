//
//  SettingsTests.swift
//  NoteCodeTests
//
//  Settings reads and writes the keys the rest of the app uses. A key
//  renamed on one side would leave the row changing nothing, or orphan what
//  a device had saved, so the stored names are pinned here.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Settings", .tags(.library))
struct SettingsTests {

    @Test("Every stored key keeps the name devices have already saved under")
    func keysAreStable() {
        #expect(SettingKeys.General.appearance.name == "appearance")
        #expect(SettingKeys.General.hapticOnSnap.name == "hapticOnSnap")
        #expect(SettingKeys.General.hotbarDock.name == "hotbarDock")
        #expect(SettingKeys.Notes.viewMode.name == "pageViewMode")
        #expect(SettingKeys.Notes.sort.name == "noteSort")
        #expect(ShowMarkdown.defaultsKey == "showMarkdown")
        #expect(SettingKeys.Drawing.fingerDraws.name == "fingerDraws")
        #expect(SettingKeys.Drawing.returnToPreviousTool.name == "returnToPreviousTool")
        #expect(SettingKeys.Drawing.selectionKind.name == "selectionKind")
        #expect(SettingKeys.Drawing.eraser.name == "eraser")
        #expect(InkPalette.defaultsKey(for: .pen) == "inkPalette")
        #expect(InkPalette.defaultsKey(for: .highlighter) == "highlighterPalette")
        #expect(SettingKeys.Code.indentWidth.name == "indentWidth")
        #expect(SettingKeys.Code.codeKeys.name == "codeKeys")
        #expect(SettingKeys.Code.lineNumbers.name == "lineNumbers")
        #expect(SettingKeys.General.iconStyle.name == "iconStyle")
        #expect(SettingKeys.Notes.newNoteOrientation.name == "newNoteOrientation")
        #expect(SettingKeys.Notes.opensAfterCreating.name == "openNoteAfterCreating")
        #expect(SettingKeys.Writing.autocorrectInProse.name == "autocorrectInProse")
        #expect(SettingKeys.Writing.headingMarkers.name == "markerDimming.headings")
        #expect(SettingKeys.Writing.bulletMarkers.name == "markerDimming.bullets")
        #expect(SettingKeys.Writing.checkboxMarkers.name == "markerDimming.checkboxes")
        #expect(SettingKeys.Writing.fenceMarkers.name == "markerDimming.fences")
    }

    @Test("The keys keysAreStable does not cover keep their names too")
    func moreKeysAreStable() {
        #expect(SettingKeys.General.accent.name == "accentColor")
        #expect(SettingKeys.Drawing.highlighterPalette.name == "highlighterPalette")
        #expect(SettingKeys.Drawing.penPalette.name == "inkPalette")
        #expect(InkingSettings.defaultsKey(for: .pen) == "penSettings")
        #expect(InkingSettings.defaultsKey(for: .highlighter) == "highlighterSettings")
        #expect(SettingKeys.Drawing.paletteSet.name == "inkPaletteSet")
        #expect(SettingKeys.Drawing.addPagesWhileDrawing.name == "addPagesWhileDrawing")
        #expect(LastCodeLanguage.defaultsKey == "lastCodeLanguage")
        #expect(WelcomeNote.madeKey == "welcomeNoteMade")
        #expect(WelcomeScreen.shownKey == "welcomeScreenShown")
        #expect(NoteMemory.placesKey == "notePlaces")
        #expect(NoteMemory.lastOpenedKey == "lastOpenedNote")
        #expect(ReviewPrompt.daysKey == "reviewPromptDays")
        #expect(ReviewPrompt.lastDayKey == "reviewPromptLastDay")
        #expect(ReviewPrompt.askedVersionKey == "reviewPromptAskedVersion")
        #expect(ReviewPrompt.askedAtKey == "reviewPromptAskedAt")
    }

    @Test("Each setting's default is what a fresh install shows")
    func defaultsAreStable() {
        #expect(AppAppearance.default.rawValue == "system")
        #expect(SettingKeys.General.hapticOnSnap.defaultValue == true)
        #expect(HotbarDock.default.rawValue == "bottom")
        #expect(PageViewMode.default.rawValue == "seamless")
        #expect(NoteSort.default.rawValue == "modified;descending")
        #expect(ShowMarkdown.whileEditing.rawValue == "whileEditing")
        #expect(SettingKeys.Notes.opensAfterCreating.defaultValue == true)
        #expect(PageOrientation.default.rawValue == "portrait")
        #expect(IconStyle().rawValue == "drawn.regular")
        #expect(SettingKeys.Code.codeKeys.defaultValue == true)
        #expect(SettingKeys.Code.indentWidth.defaultValue == 4)
        #expect(SettingKeys.Code.lineNumbers.defaultValue == false)
        #expect(SettingKeys.Writing.autocorrectInProse.defaultValue == true)
        #expect(SettingKeys.Drawing.addPagesWhileDrawing.defaultValue == true)
        #expect(EraserSettings().rawValue == "partial;small;40.0")
        #expect(SelectionKind.lasso.rawValue == "lasso")
        #expect(InkingSettings.standard(for: .pen).rawValue == "0.0,0.0,0.0,1.0;medium")
        #expect(InkingSettings.standard(for: .highlighter).rawValue == "0.9882352941176471,0.8666666666666667,0.4745098039215686,1.0;medium")
        #expect(MarkerLevel.dim.rawValue == "dim")
    }

    @Test("A key nothing has written reads as its default")
    func unsetKeysReadAsDefaults() throws {
        let suite = "SettingsTests.unset.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LastCodeLanguage.read(from: defaults) == .cpp)
        #expect(defaults.bool(forKey: WelcomeNote.madeKey) == false)
        #expect(defaults.bool(forKey: WelcomeScreen.shownKey) == false)
        #expect(defaults.object(forKey: NoteMemory.placesKey) == nil)
        #expect(defaults.object(forKey: NoteMemory.lastOpenedKey) == nil)
        #expect(ReviewPrompt(defaults: defaults).days == 0)
    }

    @Test("Appearance round-trips through its stored text, and system is the default")
    func appearanceStorage() {
        for appearance in AppAppearance.allCases {
            #expect(AppAppearance(rawValue: appearance.rawValue) == appearance)
        }
        #expect(AppAppearance(rawValue: "sepia") == nil)
        #expect(AppAppearance.default == .system)
    }

    @Test("Send Feedback needs an address, and Privacy Policy a page")
    func rowsWaitForTheirTargets() {
        // The support address is set, so About and the list's foot show both
        // mail rows.
        #expect(AppInfo.feedbackURL() != nil)
        #expect(AppInfo.featureRequestURL() != nil)
        #expect(AppInfo.feedbackURL(address: nil) == nil)
        #expect(AppInfo.feedbackURL(address: "") == nil)
        let url = AppInfo.feedbackURL(address: "hello@example.com")
        #expect(url?.scheme == "mailto")
        #expect(url?.absoluteString.hasPrefix("mailto:hello@example.com") == true)
    }

    @Test("The version reads as the store shows it: version, then build")
    func version() {
        let text = AppInfo.versionString()
        #expect(text.wholeMatch(of: /\d+(\.\d+)* \(\d+\)/) != nil, "got \(text)")
    }

    @Test("The licences of the libraries in the app are bundled")
    func acknowledgements() throws {
        let text = try #require(AppInfo.acknowledgements())
        #expect(text.contains("HighlightSwift"))
        #expect(text.contains("Stefan Britton"))
        #expect(text.contains("highlight.js"))
        #expect(text.contains("Ivan Sagalaev"))
    }

    @Test("The eraser's row says what it is set to")
    func eraserSummary() {
        var eraser = EraserSettings()
        eraser.mode = .partial
        eraser.size = .medium
        #expect(eraser.summary == "Pixel, Medium")
        eraser.mode = .wholeStroke
        #expect(eraser.summary == "Object")
    }

    @Test("Reset Colours puts both palettes back to the set's colours and touches nothing else", arguments: InkPaletteSet.allCases)
    func resetPalettes(set: InkPaletteSet) throws {
        let suite = "SettingsTests.reset.\(set.rawValue)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let custom = InkPalette([.red, .blue])
        defaults.set(custom.rawValue, forKey: InkPalette.defaultsKey(for: .pen))
        defaults.set(custom.rawValue, forKey: InkPalette.defaultsKey(for: .highlighter))
        defaults.set("dark", forKey: SettingKeys.General.appearance.name)

        InkPalette.resetStoredPalettes(to: set, in: defaults)

        let pen = defaults.string(forKey: InkPalette.defaultsKey(for: .pen)).flatMap(InkPalette.init(rawValue:))
        let marker = defaults.string(forKey: InkPalette.defaultsKey(for: .highlighter)).flatMap(InkPalette.init(rawValue:))
        #expect(pen == set.palette(for: .pen))
        #expect(marker == set.palette(for: .highlighter))
        #expect(pen != custom)
        #expect(defaults.string(forKey: SettingKeys.General.appearance.name) == "dark")
    }

    @Test("Reset Colours with no set named goes to the device's own set")
    func resetFollowsTheDevice() throws {
        let suite = "SettingsTests.resetStored"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(InkPaletteSet.original.rawValue, forKey: SettingKeys.Drawing.paletteSet.name)
        InkPalette.resetStoredPalettes(in: defaults)

        let marker = defaults.string(forKey: InkPalette.defaultsKey(for: .highlighter)).flatMap(InkPalette.init(rawValue:))
        #expect(marker == InkPaletteSet.original.palette(for: .highlighter))
    }
}

#if canImport(UIKit)

import SwiftUI
import UIKit

@Suite("Appearance setting", .serialized, .tags(.library))
@MainActor
struct AppearanceSettingTests {

    /// The device's settings for this test. The modifier reads them through
    /// `.defaultAppStorage`, so nothing here touches `UserDefaults.standard`.
    private let device = TestDefaults("Appearance")

    /// Lets SwiftUI lay out and the window take the style it was given.
    private func settle(_ window: UIWindow, _ seconds: TimeInterval = 0.4) {
        let end = Date(timeIntervalSinceNow: seconds)
        repeat {
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        } while Date() < end
    }

    @Test("The window follows the stored appearance, live, in both directions")
    func followsLive() {
        let key = SettingKeys.General.appearance.name

        device.defaults.set(AppAppearance.light.rawValue, forKey: key)
        let window = HotbarLayoutTests.makeWindow()
        let host = UIHostingController(rootView: Color.clear
            .modifier(AppearanceModifier())
            .defaultAppStorage(device.defaults))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(window)
        #expect(host.traitCollection.userInterfaceStyle == .light)

        device.defaults.set(AppAppearance.dark.rawValue, forKey: key)
        settle(window)
        #expect(host.traitCollection.userInterfaceStyle == .dark)

        device.defaults.set(AppAppearance.light.rawValue, forKey: key)
        settle(window)
        #expect(host.traitCollection.userInterfaceStyle == .light)

        // Back to System follows the device again, rather than sticking.
        device.defaults.set(AppAppearance.system.rawValue, forKey: key)
        settle(window)
        #expect(host.traitCollection.userInterfaceStyle == window.windowScene?.traitCollection.userInterfaceStyle)
    }

    @Test("A sheet over the window follows Light and then System, as the page does")
    func sheetFollowsSystemAfterAnOverride() throws {
        let key = SettingKeys.General.appearance.name

        let window = HotbarLayoutTests.makeWindow()
        device.defaults.set(AppAppearance.system.rawValue, forKey: key)
        // A SwiftUI sheet, as Settings is: the bug lived in how SwiftUI
        // presents one, and a controller presented from UIKit never showed it.
        let host = UIHostingController(rootView: Color.clear
            .sheet(isPresented: .constant(true)) { Color.clear }
            .modifier(AppearanceModifier())
            .defaultAppStorage(device.defaults))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(window, 1)

        let system = window.windowScene?.traitCollection.userInterfaceStyle ?? .light
        let other: UIUserInterfaceStyle = system == .dark ? .light : .dark

        let sheet = try #require(host.presentedViewController)
        #expect(sheet.traitCollection.userInterfaceStyle == system)

        // The reader picks the opposite of the device's appearance: the sheet
        // goes that way…
        device.defaults.set(other == .dark ? AppAppearance.dark.rawValue : AppAppearance.light.rawValue, forKey: key)
        settle(window, 1)
        #expect(sheet.traitCollection.userInterfaceStyle == other)

        // …and System takes it back to the device's. It stayed on the
        // override while `preferredColorScheme` was doing this.
        device.defaults.set(AppAppearance.system.rawValue, forKey: key)
        settle(window, 1)
        #expect(sheet.traitCollection.userInterfaceStyle == system, "the sheet is still on the override")
        #expect(host.traitCollection.userInterfaceStyle == system)
    }
}

#endif
