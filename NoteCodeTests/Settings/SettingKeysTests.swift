//
//  SettingKeysTests.swift
//  NoteCodeTests
//
//  The key tables hold the names and defaults `SettingsTests` pinned, written
//  out here as literals, so a table entry can't drift from what devices
//  saved under. And an `@AppStorage` made from an entry reads its default
//  where nothing is stored, and the stored value where something is.
//

import Foundation
import SwiftUI
import Testing
@testable import NoteCode

@Suite("Setting key tables", .tags(.library))
struct SettingKeysTests {

    @Test("Every entry keeps the name and default devices have")
    func tablesMatchThePinnedKeys() {
        typealias G = SettingKeys.General
        typealias N = SettingKeys.Notes
        typealias W = SettingKeys.Writing
        typealias C = SettingKeys.Code
        typealias D = SettingKeys.Drawing

        #expect(G.appearance.name == "appearance")
        #expect(G.appearance.defaultValue.rawValue == "system")
        #expect(G.accent.name == "accentColor")
        #expect(G.accent.defaultValue == "")
        #expect(G.hotbarDock.name == "hotbarDock")
        #expect(G.hotbarDock.defaultValue.rawValue == "bottom")
        #expect(G.hapticOnSnap.name == "hapticOnSnap")
        #expect(G.hapticOnSnap.defaultValue == true)
        #expect(G.iconStyle.name == "iconStyle")
        #expect(G.iconStyle.defaultValue.rawValue == "drawn.regular")

        #expect(N.newNoteOrientation.name == "newNoteOrientation")
        #expect(N.newNoteOrientation.defaultValue.rawValue == "portrait")
        #expect(N.opensAfterCreating.name == "openNoteAfterCreating")
        #expect(N.opensAfterCreating.defaultValue == true)
        #expect(N.viewMode.name == "pageViewMode")
        #expect(N.viewMode.defaultValue.rawValue == "seamless")
        #expect(N.sort.name == "noteSort")
        #expect(N.sort.defaultValue.rawValue == "modified;descending")

        #expect(W.showMarkdown.name == "showMarkdown")
        #expect(W.showMarkdown.defaultValue.rawValue == "whileEditing")
        #expect(W.autocorrectInProse.name == "autocorrectInProse")
        #expect(W.autocorrectInProse.defaultValue == true)
        #expect(W.headingMarkers.name == "markerDimming.headings")
        #expect(W.bulletMarkers.name == "markerDimming.bullets")
        #expect(W.checkboxMarkers.name == "markerDimming.checkboxes")
        #expect(W.fenceMarkers.name == "markerDimming.fences")
        for marker in [W.headingMarkers, W.bulletMarkers, W.checkboxMarkers, W.fenceMarkers] {
            #expect(marker.defaultValue.rawValue == "dim")
        }

        #expect(C.indentWidth.name == "indentWidth")
        #expect(C.indentWidth.defaultValue == 4)
        #expect(C.codeKeys.name == "codeKeys")
        #expect(C.codeKeys.defaultValue == true)
        #expect(C.lineNumbers.name == "lineNumbers")
        #expect(C.lineNumbers.defaultValue == false)

        #expect(D.fingerDraws.name == "fingerDraws")
        #expect(D.fingerDraws.defaultValue == true)
        #expect(D.returnToPreviousTool.name == "returnToPreviousTool")
        #expect(D.returnToPreviousTool.defaultValue == false)
        #expect(D.eraser.name == "eraser")
        #expect(D.eraser.defaultValue.rawValue == "partial;small;40.0")
        #expect(D.addPagesWhileDrawing.name == "addPagesWhileDrawing")
        #expect(D.addPagesWhileDrawing.defaultValue == true)
        #expect(D.selectionKind.name == "selectionKind")
        #expect(D.selectionKind.defaultValue.rawValue == "lasso")
        #expect(D.paletteSet.name == "inkPaletteSet")
        #expect(D.paletteSet.defaultValue == "")
        #expect(D.penPalette.name == "inkPalette")
        #expect(D.highlighterPalette.name == "highlighterPalette")
        #expect(D.palette(for: .pen).name == "inkPalette")
        #expect(D.palette(for: .highlighter).name == "highlighterPalette")
        #expect(D.penSettings.name == "penSettings")
        #expect(D.highlighterSettings.name == "highlighterSettings")
        #expect(D.inking(for: .pen).name == "penSettings")
        #expect(D.inking(for: .highlighter).name == "highlighterSettings")
        #expect(D.penSettings.defaultValue.rawValue == "0.0,0.0,0.0,1.0;medium")
        #expect(D.highlighterSettings.defaultValue.rawValue == "0.9882352941176471,0.8666666666666667,0.4745098039215686,1.0;medium")
        #expect(D.penPalette.defaultValue.rawValue == InkPalette(InkColor.penShades.map(\.color)).rawValue)
        #expect(D.highlighterPalette.defaultValue.rawValue == InkPalette(InkColor.highlighterShades.map(\.color)).rawValue)
    }

    @Test("The owners' defaults come from the tables")
    func ownerDefaultsComeFromTheTables() {
        #expect(AppAppearance.default == SettingKeys.General.appearance.defaultValue)
        #expect(HotbarDock.default == SettingKeys.General.hotbarDock.defaultValue)
        #expect(PageViewMode.default == SettingKeys.Notes.viewMode.defaultValue)
        #expect(NoteSort.default == SettingKeys.Notes.sort.defaultValue)
        #expect(InkPalette.standard(for: .pen) == SettingKeys.Drawing.penPalette.defaultValue)
        #expect(InkPalette.standard(for: .highlighter) == SettingKeys.Drawing.highlighterPalette.defaultValue)
        #expect(InkingSettings.standard(for: .highlighter) == SettingKeys.Drawing.highlighterSettings.defaultValue)
    }

    @Test("An @AppStorage from an entry reads its default, then what is stored")
    func appStorageFromAnEntry() throws {
        let suite = "SettingKeysTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let flag = AppStorage(SettingKeys.Code.codeKeys, store: defaults)
        let width = AppStorage(SettingKeys.Code.indentWidth, store: defaults)
        let accent = AppStorage(SettingKeys.General.accent, store: defaults)
        let mode = AppStorage(SettingKeys.Notes.viewMode, store: defaults)
        let eraser = AppStorage(SettingKeys.Drawing.eraser, store: defaults)
        #expect(flag.wrappedValue == true)
        #expect(width.wrappedValue == 4)
        #expect(accent.wrappedValue == "")
        #expect(mode.wrappedValue == .seamless)
        #expect(eraser.wrappedValue == EraserSettings())

        defaults.set(false, forKey: "codeKeys")
        defaults.set(2, forKey: "indentWidth")
        defaults.set("#336699", forKey: "accentColor")
        defaults.set("print", forKey: "pageViewMode")
        #expect(flag.wrappedValue == false)
        #expect(width.wrappedValue == 2)
        #expect(accent.wrappedValue == "#336699")
        #expect(mode.wrappedValue == .print)
    }
}
