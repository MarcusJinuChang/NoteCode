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

@Suite("Settings")
struct SettingsTests {

    @Test("Every stored key keeps the name devices have already saved under")
    func keysAreStable() {
        #expect(AppAppearance.defaultsKey == "appearance")
        #expect(SnapHaptic.defaultsKey == "hapticOnSnap")
        #expect(HotbarDock.defaultsKey == "hotbarDock")
        #expect(PageViewMode.defaultsKey == "pageViewMode")
        #expect(NoteSort.defaultsKey == "noteSort")
        #expect(ShowMarkdown.defaultsKey == "showMarkdown")
        #expect(NoteEditor.fingerDrawsKey == "fingerDraws")
        #expect(NoteEditor.returnToPreviousToolKey == "returnToPreviousTool")
        #expect(SelectionKind.defaultsKey == "selectionKind")
        #expect(EraserSettings.defaultsKey == "eraser")
        #expect(InkPalette.defaultsKey(for: .pen) == "inkPalette")
        #expect(InkPalette.defaultsKey(for: .highlighter) == "highlighterPalette")
        #expect(CodeIndent.widthKey == "indentWidth")
        #expect(CodeKeys.enabledKey == "codeKeys")
        #expect(LineNumbers.defaultsKey == "lineNumbers")
        #expect(IconStyle.defaultsKey == "iconStyle")
        #expect(NewNotes.defaultsKey == "newNoteOrientation")
        #expect(NewNotes.opensAfterCreatingKey == "openNoteAfterCreating")
        #expect(PaperSetup.defaultStyleKey == "defaultPaper")
        #expect(PaperSetup.defaultSpacingKey == "defaultPaperSpacing")
        #expect(PaperSetup.defaultStrengthKey == "defaultPaperStrength")
        #expect(TextRewritingPolicy.proseDefaultsKey == "autocorrectInProse")
        #expect(MarkerDimming.headingsKey == "markerDimming.headings")
        #expect(MarkerDimming.bulletsKey == "markerDimming.bullets")
        #expect(MarkerDimming.checkboxesKey == "markerDimming.checkboxes")
        #expect(MarkerDimming.fencesKey == "markerDimming.fences")
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
        defaults.set("dark", forKey: AppAppearance.defaultsKey)

        InkPalette.resetStoredPalettes(to: set, in: defaults)

        let pen = defaults.string(forKey: InkPalette.defaultsKey(for: .pen)).flatMap(InkPalette.init(rawValue:))
        let marker = defaults.string(forKey: InkPalette.defaultsKey(for: .highlighter)).flatMap(InkPalette.init(rawValue:))
        #expect(pen == set.palette(for: .pen))
        #expect(marker == set.palette(for: .highlighter))
        #expect(pen != custom)
        #expect(defaults.string(forKey: AppAppearance.defaultsKey) == "dark")
    }

    @Test("Reset Colours with no set named goes to the device's own set")
    func resetFollowsTheDevice() throws {
        let suite = "SettingsTests.resetStored"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(InkPaletteSet.original.rawValue, forKey: InkPaletteSet.defaultsKey)
        InkPalette.resetStoredPalettes(in: defaults)

        let marker = defaults.string(forKey: InkPalette.defaultsKey(for: .highlighter)).flatMap(InkPalette.init(rawValue:))
        #expect(marker == InkPaletteSet.original.palette(for: .highlighter))
    }
}

#if canImport(UIKit)

import SwiftUI
import UIKit

@Suite("Appearance setting", .serialized)
@MainActor
struct AppearanceSettingTests {

    /// Runs `body` with the device's appearance stored as `value`, and puts
    /// back what it had.
    private func settle(_ window: UIWindow, _ seconds: TimeInterval = 0.4) {
        let end = Date(timeIntervalSinceNow: seconds)
        repeat {
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        } while Date() < end
    }

    @Test("The window follows the stored appearance, live, in both directions")
    func followsLive() {
        let key = AppAppearance.defaultsKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(AppAppearance.light.rawValue, forKey: key)
        let window = HotbarLayoutTests.makeWindow()
        let host = UIHostingController(rootView: Color.clear.modifier(AppearanceModifier()))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(window)
        #expect(host.traitCollection.userInterfaceStyle == .light)

        UserDefaults.standard.set(AppAppearance.dark.rawValue, forKey: key)
        settle(window)
        #expect(host.traitCollection.userInterfaceStyle == .dark)

        UserDefaults.standard.set(AppAppearance.light.rawValue, forKey: key)
        settle(window)
        #expect(host.traitCollection.userInterfaceStyle == .light)

        // Back to System follows the device again, rather than sticking.
        UserDefaults.standard.set(AppAppearance.system.rawValue, forKey: key)
        settle(window)
        #expect(host.traitCollection.userInterfaceStyle == window.windowScene?.traitCollection.userInterfaceStyle)
    }

    @Test("A sheet over the window follows Light and then System, as the page does")
    func sheetFollowsSystemAfterAnOverride() throws {
        let key = AppAppearance.defaultsKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let window = HotbarLayoutTests.makeWindow()
        UserDefaults.standard.set(AppAppearance.system.rawValue, forKey: key)
        // A SwiftUI sheet, as Settings is: the bug lived in how SwiftUI
        // presents one, and a controller presented from UIKit never showed it.
        let host = UIHostingController(rootView: Color.clear
            .sheet(isPresented: .constant(true)) { Color.clear }
            .modifier(AppearanceModifier()))
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
        UserDefaults.standard.set(other == .dark ? AppAppearance.dark.rawValue : AppAppearance.light.rawValue, forKey: key)
        settle(window, 1)
        #expect(sheet.traitCollection.userInterfaceStyle == other)

        // …and System takes it back to the device's. It stayed on the
        // override while `preferredColorScheme` was doing this.
        UserDefaults.standard.set(AppAppearance.system.rawValue, forKey: key)
        settle(window, 1)
        #expect(sheet.traitCollection.userInterfaceStyle == system, "the sheet is still on the override")
        #expect(host.traitCollection.userInterfaceStyle == system)
    }
}

#endif
