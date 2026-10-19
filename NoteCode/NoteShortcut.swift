//
//  NoteShortcut.swift
//  NoteCode
//
//  Every keyboard shortcut in one table, so none can collide with another and
//  each shows up when ⌘ is held.
//

import SwiftUI

/// A keyboard shortcut, and the name it is listed under.
///
/// One table, read by the app's menu bar (`NoteCommands`) and by the two
/// places that already owned a shortcut (⌘F in the header's ••• menu, ⌘, for
/// Settings). Two buttons answering the same keys means neither fires, so the
/// table is where that is ruled out (`NoteShortcutTests.noTwoShareKeys`).
///
/// Listed in the ⌘ overlay because they are buttons in the menu bar: iPadOS
/// builds that overlay from the menu items' key equivalents and titles, which
/// is the discoverability title a `UIKeyCommand` would carry.
enum NoteShortcut: CaseIterable, Sendable {
    case undo, redo
    case bold, italic, inlineCode
    case heading1, heading2, heading3, body
    case strikethrough, underline, bulletedList, codeBlock
    case runBlock, copyBlock
    case toggleMode
    case pen, highlighter, eraser, lasso
    case thinner, thicker
    case seamless, compressed, printLayout
    case outline, biggerText, smallerText
    case find, print
    case newNote, newFolder, searchNotes, noteList, home
    case settings

    var title: String {
        switch self {
        case .undo:          "Undo"
        case .redo:          "Redo"
        case .bold:          "Bold"
        case .italic:        "Italic"
        case .inlineCode:    "Inline Code"
        case .heading1:      "Heading 1"
        case .heading2:      "Heading 2"
        case .heading3:      "Heading 3"
        case .body:          "Body"
        case .strikethrough: "Strikethrough"
        case .underline:     "Underline"
        case .bulletedList:  "Bulleted List"
        case .codeBlock:     "Code Block"
        case .runBlock:      "Run Block"
        case .copyBlock:     "Copy Block"
        case .toggleMode:    "Text / Draw"
        case .pen:           "Pen"
        case .highlighter:   "Highlighter"
        case .eraser:        "Eraser"
        case .lasso:         "Lasso"
        case .thinner:       "Thinner"
        case .thicker:       "Thicker"
        case .seamless:      "Seamless"
        case .compressed:    "Compressed"
        case .printLayout:   "Print Layout"
        case .outline:       "Outline"
        case .biggerText:    "Bigger Text"
        case .smallerText:   "Smaller Text"
        case .find:          "Find in Note"
        case .print:         "Print…"
        case .newNote:       "New Note"
        case .newFolder:     "New Folder"
        case .searchNotes:   "Search Notes"
        case .noteList:      "Show Note List"
        case .home:          "Home"
        case .settings:      "Settings…"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .undo, .redo:   "z"
        case .bold:          "b"
        case .italic:        "i"
        case .inlineCode:    "e"
        case .heading1:      "1"
        case .heading2:      "2"
        case .heading3:      "3"
        case .body:          "0"
        case .strikethrough: "x"
        case .underline:     "u"
        case .bulletedList:  "l"
        case .codeBlock:     "k"
        case .runBlock:      "r"
        case .copyBlock:     "c"
        case .toggleMode:    "d"
        case .pen:           "p"
        case .highlighter:   "h"
        case .eraser:        "e"
        case .lasso:         "l"
        case .thinner:       "["
        case .thicker:       "]"
        case .seamless:      "1"
        case .compressed:    "2"
        case .printLayout:   "3"
        case .outline:       "o"
        case .biggerText:    "+"
        case .smallerText:   "-"
        case .find:          "f"
        case .print:         "p"
        case .newNote:       "n"
        case .newFolder:     "n"
        case .searchNotes:   "f"
        case .noteList:      "s"
        case .home:          "h"
        case .settings:      ","
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .undo, .bold, .italic, .underline, .inlineCode, .runBlock, .seamless, .compressed, .printLayout,
             .find, .print, .newNote, .settings, .biggerText, .smallerText:
            .command
        case .redo, .strikethrough, .bulletedList, .codeBlock, .copyBlock, .toggleMode,
             .newFolder, .searchNotes, .home:
            [.command, .shift]
        case .heading1, .heading2, .heading3, .body:
            [.command, .option]
        case .noteList, .outline:
            [.command, .control]
        case .pen, .highlighter, .eraser, .lasso, .thinner, .thicker:
            []
        }
    }

    /// Single keys with nothing held, which are typing when a text field has
    /// the keyboard. They work in ink mode, with no text being edited, and
    /// the menu turns them off the rest of the time (`NoteCommands`).
    var isPlainKey: Bool {
        modifiers.isEmpty
    }

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(key, modifiers: modifiers)
    }

    /// The same shortcut as a comparable pair, for the table's tests.
    var chord: String {
        var held = ""
        if modifiers.contains(.control) { held += "⌃" }
        if modifiers.contains(.option) { held += "⌥" }
        if modifiers.contains(.shift) { held += "⇧" }
        if modifiers.contains(.command) { held += "⌘" }
        return held + String(key.character).uppercased()
    }
}

extension View {
    /// Gives a control one of the table's shortcuts.
    func keyboardShortcut(_ shortcut: NoteShortcut) -> some View {
        keyboardShortcut(shortcut.keyboardShortcut)
    }
}
