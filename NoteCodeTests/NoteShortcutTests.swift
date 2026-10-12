//
//  NoteShortcutTests.swift
//  NoteCodeTests
//
//  The shortcut table: what the brief lists, with no key answering two things.
//

import SwiftUI
import Testing
@testable import NoteCode

@Suite("Keyboard shortcuts")
@MainActor
struct NoteShortcutTests {

    /// The brief's table, written out by hand so a typo in `NoteShortcut`
    /// can't also be in the expectation.
    static let expected: [(NoteShortcut, String)] = [
        (.undo, "⌘Z"), (.redo, "⇧⌘Z"),
        (.bold, "⌘B"), (.italic, "⌘I"), (.inlineCode, "⌘E"),
        (.heading1, "⌥⌘1"), (.heading2, "⌥⌘2"), (.heading3, "⌥⌘3"), (.body, "⌥⌘0"),
        (.strikethrough, "⇧⌘X"), (.bulletedList, "⇧⌘L"), (.codeBlock, "⇧⌘K"),
        (.runBlock, "⌘R"), (.copyBlock, "⇧⌘C"),
        (.toggleMode, "⇧⌘D"),
        (.pen, "P"), (.highlighter, "H"), (.eraser, "E"), (.lasso, "L"),
        (.thinner, "["), (.thicker, "]"),
        (.seamless, "⌘1"), (.compressed, "⌘2"), (.printLayout, "⌘3"),
        (.find, "⌘F"), (.print, "⌘P"),
        (.newNote, "⌘N"), (.newFolder, "⇧⌘N"), (.searchNotes, "⇧⌘F"),
        (.noteList, "⌃⌘S"), (.settings, "⌘,"),
    ]

    @Test("Every shortcut is the one the brief lists, and the table has no others")
    func matchesTheBrief() {
        for (shortcut, chord) in Self.expected {
            #expect(shortcut.chord == chord, "\(shortcut.title)")
        }
        #expect(Self.expected.count == NoteShortcut.allCases.count)
    }

    @Test("No two shortcuts are the same keys")
    func noTwoShareKeys() {
        var seen: [String: NoteShortcut] = [:]
        for shortcut in NoteShortcut.allCases {
            let other = seen[shortcut.chord]
            #expect(other == nil, "\(shortcut.title) and \(other?.title ?? "") are both \(shortcut.chord)")
            seen[shortcut.chord] = shortcut
        }
    }

    @Test("Every shortcut has a title, which is what ⌘ lists it under")
    func titled() {
        for shortcut in NoteShortcut.allCases {
            #expect(!shortcut.title.isEmpty)
        }
    }

    @Test("Only the ink keys are bare, because a bare key is typing in a field")
    func bareKeys() {
        let bare = NoteShortcut.allCases.filter(\.isPlainKey)
        #expect(Set(bare) == [.pen, .highlighter, .eraser, .lasso, .thinner, .thicker])
    }

    @Test("The view modes' shortcuts are ⌘1 to ⌘3, in the menu's order")
    func viewModes() {
        #expect(PageViewMode.seamless.shortcut == .seamless)
        #expect(PageViewMode.compressed.shortcut == .compressed)
        #expect(PageViewMode.print.shortcut == .printLayout)
    }

    @Test("The shortcuts that were already in the app are the table's")
    func existingOnesMoved() {
        #expect(NoteShortcut.find.chord == "⌘F")
        #expect(NoteShortcut.settings.chord == "⌘,")
    }
}

