//
//  InkToolPersistenceTests.swift
//  NoteCodeTests
//
//  T5, before 2P5: the ink tool's settings round trip as it is today, through
//  `InkToolPersistence` (Ink/HotbarPrimitives.swift). The hotbar changes the
//  open note's editor; the modifier writes what it changed to the device's
//  settings, which the next note's editor starts from and Settings › Drawing
//  reads. Settings writes the same keys over an open note, and some of them
//  reach it. `FingerDrawsPersistenceTests` covers Finger Draws through the
//  whole note page; this pins every tool setting through the modifier alone.
//  The settings are a `TestDefaults`, handed in by `.defaultAppStorage`.
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

    /// One open note's editor, with the modifier the note page puts on it.
    @MainActor
    private final class OpenNote {
        let editor = NoteEditor()
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))

        /// - Parameter fingerDraws: what the editor has before the modifier
        ///   has read the settings.
        init(defaults: UserDefaults, fingerDraws: Bool) {
            editor.fingerDraws = fingerDraws
            let root = Color.clear
                .modifier(InkToolPersistence(editor: editor))
                .defaultAppStorage(defaults)
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
        }

        func close() {
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    /// Opens a note and waits for its `onAppear` to have set the editor:
    /// `sentinel` puts Finger Draws the other way first, so its arrival says
    /// the stored settings have been read.
    private func openNote() async throws -> OpenNote {
        let stored = device.defaults.object(forKey: NoteEditor.fingerDrawsKey) as? Bool ?? true
        let note = OpenNote(defaults: device.defaults, fingerDraws: !stored)
        let arrived = await waitFor { note.editor.fingerDraws == stored }
        try #require(arrived, "onAppear never set the editor")
        return note
    }

    private func string(_ key: String) -> String? {
        device.defaults.string(forKey: key)
    }

    private static let red = InkColor(red: 0.8, green: 0.1, blue: 0.1)
    private static let green = InkColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 0.5)

    @Test("With nothing stored, a note opens on the standard tools")
    func standardTools() async throws {
        let note = try await openNote()
        defer { note.close() }
        let tool = note.editor.inkTool

        #expect(tool.pen == InkingSettings.standard(for: .pen))
        #expect(tool.highlighter == InkingSettings.standard(for: .highlighter))
        #expect(tool.eraser == EraserSettings())
        #expect(tool.selectionKind == .lasso)
        #expect(note.editor.fingerDraws)
        #expect(!note.editor.returnsToPreviousTool)
        // Opening a note writes nothing.
        #expect(string(InkingSettings.defaultsKey(for: .pen)) == nil)
        #expect(string(EraserSettings.defaultsKey) == nil)
    }

    @Test("What the hotbar sets in one note is stored, and the next note opens with it")
    func hotbarToNextNote() async throws {
        let first = try await openNote()
        first.editor.inkTool.pen = InkingSettings(color: Self.red, width: .bold)
        first.editor.inkTool.highlighter = InkingSettings(color: Self.green, width: .fine)
        var eraser = EraserSettings()
        eraser.mode = .wholeStroke
        eraser.size = .custom
        eraser.customWidth = 60
        first.editor.inkTool.eraser = eraser
        first.editor.inkTool.selectionKind = .rectangle
        first.editor.fingerDraws = false

        let written = await waitFor { device.defaults.object(forKey: NoteEditor.fingerDrawsKey) as? Bool == false }
        try #require(written)
        // The keys Settings › Drawing reads, in the form it reads them.
        #expect(string(InkingSettings.defaultsKey(for: .pen)) == InkingSettings(color: Self.red, width: .bold).rawValue)
        #expect(string(InkingSettings.defaultsKey(for: .highlighter)) == InkingSettings(color: Self.green, width: .fine).rawValue)
        #expect(string(EraserSettings.defaultsKey).flatMap(EraserSettings.init(rawValue:)) == eraser)
        #expect(string(SelectionKind.defaultsKey) == SelectionKind.rectangle.rawValue)
        first.close()

        let second = try await openNote()
        defer { second.close() }
        let tool = second.editor.inkTool
        #expect(tool.pen == InkingSettings(color: Self.red, width: .bold))
        #expect(tool.highlighter == InkingSettings(color: Self.green, width: .fine))
        #expect(tool.eraser == eraser)
        #expect(tool.selectionKind == .rectangle)
        #expect(!second.editor.fingerDraws)
    }

    @Test("The tool in hand is not stored: the next note opens on the pen")
    func toolKindNotStored() async throws {
        let first = try await openNote()
        first.editor.inkTool.kind = .eraser
        // Something that is stored, to know the modifier has had its turn.
        first.editor.fingerDraws = false
        let written = await waitFor { device.defaults.object(forKey: NoteEditor.fingerDrawsKey) as? Bool == false }
        try #require(written)
        first.close()

        let second = try await openNote()
        defer { second.close() }
        #expect(second.editor.inkTool.kind == .pen)
    }

    @Test("Settings › Drawing over an open note reaches it: eraser, Finger Draws, Return to Previous Tool, the highlighter")
    func settingsReachTheOpenNote() async throws {
        let note = try await openNote()
        defer { note.close() }

        var eraser = EraserSettings()
        eraser.mode = .wholeStroke
        eraser.size = .large
        device.defaults.set(eraser.rawValue, forKey: EraserSettings.defaultsKey)
        device.defaults.set(true, forKey: NoteEditor.returnToPreviousToolKey)
        // A colour set rewrites the highlighter's remembered colour.
        let highlighter = InkingSettings(color: Self.green, width: .medium)
        device.defaults.set(highlighter.rawValue, forKey: InkingSettings.defaultsKey(for: .highlighter))
        device.defaults.set(false, forKey: NoteEditor.fingerDrawsKey)

        let reached = await waitFor {
            !note.editor.fingerDraws
                && note.editor.inkTool.eraser == eraser
                && note.editor.returnsToPreviousTool
                && note.editor.inkTool.highlighter == highlighter
        }
        #expect(reached)
    }

    @Test("A pen or selection kind written over an open note does not reach it")
    func penAndSelectionNotPushed() async throws {
        // Pinned as found, not a decision: the refactor keeps it, and changing it is an F fix.
        let note = try await openNote()
        defer { note.close() }

        device.defaults.set(InkingSettings(color: Self.red, width: .bold).rawValue, forKey: InkingSettings.defaultsKey(for: .pen))
        device.defaults.set(SelectionKind.rectangle.rawValue, forKey: SelectionKind.defaultsKey)
        // Written with them, and pushed: once it lands, the others had their chance.
        device.defaults.set(false, forKey: NoteEditor.fingerDrawsKey)
        let landed = await waitFor { !note.editor.fingerDraws }
        try #require(landed)

        // Nothing in Settings writes these two today; only the next note reads them.
        #expect(note.editor.inkTool.pen == InkingSettings.standard(for: .pen))
        #expect(note.editor.inkTool.selectionKind == .lasso)
    }

    @Test("Return to Previous Tool goes one way: the editor's own change is not stored")
    func returnToPreviousToolOneWay() async throws {
        // Pinned as found, not a decision: the refactor keeps it, and changing it is an F fix.
        let note = try await openNote()
        defer { note.close() }

        note.editor.returnsToPreviousTool = true
        // Something that is stored, to know the modifier has had its turn.
        note.editor.fingerDraws = false
        let written = await waitFor { device.defaults.object(forKey: NoteEditor.fingerDrawsKey) as? Bool == false }
        try #require(written)

        #expect(device.defaults.object(forKey: NoteEditor.returnToPreviousToolKey) == nil)
    }
}

#endif
