//
//  InkToolPersistenceTests.swift
//  NoteCodeTests
//
//  The ink tool's settings round trip: the hotbar changes the open note's
//  editor, `InkToolStore` writes what changed to the device's settings,
//  which the next note's editor starts from and Settings › Drawing reads.
//  Settings writes the same keys over an open note, and some of them reach
//  it. Written in T5 against `InkToolPersistence`, and kept through 2P5,
//  which put the store in its place: the assertions are the same, only how
//  a note's editor is given its settings has changed.
//  `FingerDrawsPersistenceTests` covers Finger Draws through the whole note
//  page; this pins every tool setting through the editor and the store.
//  The settings are a `TestDefaults`.
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("The ink tool's settings round trip", .serialized, .tags(.ink))
@MainActor
struct InkToolPersistenceTests {

    private let device = TestDefaults("InkTool")

    /// One open note's editor, with the store the device gives it.
    @MainActor
    private final class OpenNote {
        let editor: NoteEditor

        init(defaults: UserDefaults) {
            editor = NoteEditor(inkTools: InkToolStore(defaults: defaults))
        }
    }

    private func openNote() -> OpenNote {
        OpenNote(defaults: device.defaults)
    }

    private func string(_ key: String) -> String? {
        device.defaults.string(forKey: key)
    }

    private static let red = InkColor(red: 0.8, green: 0.1, blue: 0.1)
    private static let green = InkColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 0.5)

    @Test("With nothing stored, a note opens on the standard tools")
    func standardTools() {
        let note = openNote()
        let tool = note.editor.inkTool

        #expect(tool.pen == InkingSettings.standard(for: .pen))
        #expect(tool.highlighter == InkingSettings.standard(for: .highlighter))
        #expect(tool.eraser == EraserSettings())
        #expect(tool.selectionKind == .lasso)
        #expect(note.editor.fingerDraws)
        #expect(!note.editor.returnsToPreviousTool)
        // Opening a note writes nothing.
        #expect(string(InkingSettings.defaultsKey(for: .pen)) == nil)
        #expect(string(SettingKeys.Drawing.eraser.name) == nil)
    }

    @Test("What the hotbar sets in one note is stored, and the next note opens with it")
    func hotbarToNextNote() {
        let first = openNote()
        first.editor.inkTool.pen = InkingSettings(color: Self.red, width: .bold)
        first.editor.inkTool.highlighter = InkingSettings(color: Self.green, width: .fine)
        var eraser = EraserSettings()
        eraser.mode = .wholeStroke
        eraser.size = .custom
        eraser.customWidth = 60
        first.editor.inkTool.eraser = eraser
        first.editor.inkTool.selectionKind = .rectangle
        first.editor.fingerDraws = false

        // The keys Settings › Drawing reads, in the form it reads them.
        #expect(string(InkingSettings.defaultsKey(for: .pen)) == InkingSettings(color: Self.red, width: .bold).rawValue)
        #expect(string(InkingSettings.defaultsKey(for: .highlighter)) == InkingSettings(color: Self.green, width: .fine).rawValue)
        #expect(string(SettingKeys.Drawing.eraser.name).flatMap(EraserSettings.init(rawValue:)) == eraser)
        #expect(string(SettingKeys.Drawing.selectionKind.name) == SelectionKind.rectangle.rawValue)
        #expect(device.defaults.object(forKey: SettingKeys.Drawing.fingerDraws.name) as? Bool == false)

        let second = openNote()
        let tool = second.editor.inkTool
        #expect(tool.pen == InkingSettings(color: Self.red, width: .bold))
        #expect(tool.highlighter == InkingSettings(color: Self.green, width: .fine))
        #expect(tool.eraser == eraser)
        #expect(tool.selectionKind == .rectangle)
        #expect(!second.editor.fingerDraws)
    }

    @Test("The tool in hand is not stored: the next note opens on the pen")
    func toolKindNotStored() {
        let first = openNote()
        first.editor.inkTool.kind = .eraser
        // Something that is stored, to know the store has had its turn.
        first.editor.fingerDraws = false
        #expect(device.defaults.object(forKey: SettingKeys.Drawing.fingerDraws.name) as? Bool == false)

        let second = openNote()
        #expect(second.editor.inkTool.kind == .pen)
    }

    @Test("Settings › Drawing over an open note reaches it: eraser, Finger Draws, Return to Previous Tool, the highlighter, the palettes")
    func settingsReachTheOpenNote() async throws {
        let note = openNote()

        var eraser = EraserSettings()
        eraser.mode = .wholeStroke
        eraser.size = .large
        device.defaults.set(eraser.rawValue, forKey: SettingKeys.Drawing.eraser.name)
        device.defaults.set(true, forKey: SettingKeys.Drawing.returnToPreviousTool.name)
        // A colour set rewrites the highlighter's remembered colour.
        let highlighter = InkingSettings(color: Self.green, width: .medium)
        device.defaults.set(highlighter.rawValue, forKey: InkingSettings.defaultsKey(for: .highlighter))
        device.defaults.set(false, forKey: SettingKeys.Drawing.fingerDraws.name)
        // And a reset, or a set, rewrites the palettes.
        let palette = InkPalette([Self.red])
        device.defaults.set(palette.rawValue, forKey: InkPalette.defaultsKey(for: .pen))

        let reached = await waitFor {
            !note.editor.fingerDraws
                && note.editor.inkTool.eraser == eraser
                && note.editor.returnsToPreviousTool
                && note.editor.inkTool.highlighter == highlighter
                && note.editor.inkTools[palette: .pen] == palette
        }
        #expect(reached)
    }

    @Test("A pen or selection kind written over an open note does not reach it")
    func penAndSelectionNotPushed() async throws {
        // Pinned as found, not a decision: the refactor keeps it, and changing it is an F fix.
        let note = openNote()

        device.defaults.set(InkingSettings(color: Self.red, width: .bold).rawValue, forKey: InkingSettings.defaultsKey(for: .pen))
        device.defaults.set(SelectionKind.rectangle.rawValue, forKey: SettingKeys.Drawing.selectionKind.name)
        // Written with them, and pushed: once it lands, the others had their chance.
        device.defaults.set(false, forKey: SettingKeys.Drawing.fingerDraws.name)
        let landed = await waitFor { !note.editor.fingerDraws }
        try #require(landed)

        // Nothing in Settings writes these two today; only the next note reads them.
        #expect(note.editor.inkTool.pen == InkingSettings.standard(for: .pen))
        #expect(note.editor.inkTool.selectionKind == .lasso)
    }

    @Test("Settings writes through the store the open note reads: no echo, no second copy")
    func settingsShareTheStore() {
        let tools = InkToolStore(defaults: device.defaults)
        let note = NoteEditor(inkTools: tools)

        // What Settings › Drawing's toggles do.
        tools.fingerDraws = false
        tools.returnsToPreviousTool = true
        var eraser = EraserSettings()
        eraser.mode = .wholeStroke
        tools.eraser = eraser

        #expect(!note.fingerDraws)
        #expect(note.returnsToPreviousTool)
        #expect(note.inkTool.eraser == eraser)
        #expect(device.defaults.object(forKey: SettingKeys.Drawing.fingerDraws.name) as? Bool == false)
        #expect(device.defaults.object(forKey: SettingKeys.Drawing.returnToPreviousTool.name) as? Bool == true)
        #expect(string(SettingKeys.Drawing.eraser.name).flatMap(EraserSettings.init(rawValue:)) == eraser)
    }

    @Test("A palette the swatches change is stored, and the next note has it")
    func paletteRoundTrip() {
        let first = openNote()
        let palette = InkPalette([Self.red, Self.green])
        first.editor.inkTools[palette: .highlighter] = palette
        #expect(string(SettingKeys.Drawing.highlighterPalette.name) == palette.rawValue)
        // The pen's is untouched.
        #expect(string(SettingKeys.Drawing.penPalette.name) == nil)

        let second = openNote()
        #expect(second.editor.inkTools[palette: .highlighter] == palette)
        #expect(second.editor.inkTools[palette: .pen] == InkPalette.standard(for: .pen))
    }

    @Test("With no device behind it, a store keeps its settings in memory only")
    func memoryOnly() {
        let editor = NoteEditor()
        editor.inkTool.pen = InkingSettings(color: Self.red, width: .bold)
        editor.fingerDraws = false
        let other = NoteEditor()
        #expect(other.inkTool.pen == InkingSettings.standard(for: .pen))
        #expect(other.fingerDraws)
    }
}

#endif
