//
//  NoteCommands.swift
//  NoteCode
//
//  The app's menu bar, and so its keyboard shortcuts.
//

import Observation
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - What the window and the open note offer

/// Something the window asks the note list to do once it is on screen.
///
/// The list owns the name alert and the search field, and it may not exist
/// yet (it slides away over a note), so a command raises a request and the
/// list answers it when it appears.
enum ListRequest: Equatable {
    case newFolder
    case searchNotes
    /// Open this folder in the list and scroll it into view: a tap on a
    /// folder's tile on Home.
    case showFolder(PersistentIdentifier)
}

/// What ⌘N and its neighbours do, handed to the menu bar by the window in
/// front (`ContentView`). A command can't see a window's state.
struct WindowActions {
    var newNote: () -> Void
    var newFolder: () -> Void
    var searchNotes: () -> Void
    var toggleNoteList: () -> Void

    /// ⇧⌘H: close the open note and show Home.
    var goHome: () -> Void

    /// True while a sheet is over the window. Settings has text fields, and
    /// the note under it is not where a bare letter should go.
    var isCovered = false
}

#if canImport(UIKit)
/// The open note, handed to the menu bar by its page (`PageDetailView`).
struct OpenNote {
    var editor: NoteEditor
    var viewMode: Binding<PageViewMode>
    var printNote: () -> Void
}
#endif

private extension FocusedValues {
    @Entry var windowActions: WindowActions?
#if canImport(UIKit)
    @Entry var openNote: OpenNote?
#endif
}

extension View {
    /// Offers the window's actions to the menu bar.
    func windowActions(_ actions: WindowActions) -> some View {
        focusedSceneValue(\.windowActions, actions)
    }

#if canImport(UIKit)
    /// Offers the open note to the menu bar.
    func openNote(_ note: OpenNote) -> some View {
        focusedSceneValue(\.openNote, note)
    }
#endif
}

// MARK: - Whether a field has the keyboard

#if canImport(UIKit)
/// Whether any text field or text view has the keyboard, anywhere in the app.
///
/// A shortcut of one bare letter is typing when a field has the keyboard.
/// The menu can't ask UIKit that when it builds, so this watches the begin
/// and end notifications every `UITextField` and `UITextView` post, and
/// `NoteCommands` turns P, H, E, L, [ and ] off while it is true. The search
/// field, a title being renamed, an alert's field and Settings' fields all
/// count, without any of them knowing.
@MainActor @Observable
final class TextInputActivity {

    static let shared = TextInputActivity()

    private(set) var isEditing = false

    /// The fields that have begun and not ended, by identity. A second field
    /// can begin before the first ends (a tap from one to the other), so a
    /// count of one would turn the shortcuts back on mid-edit.
    @ObservationIgnored private var active: Set<ObjectIdentifier> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func began(_ field: AnyObject) {
        active.insert(ObjectIdentifier(field))
        update()
    }

    func ended(_ field: AnyObject) {
        active.remove(ObjectIdentifier(field))
        update()
    }

    /// Starts listening. Idempotent.
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let pairs: [(Notification.Name, Bool)] = [
            (UITextField.textDidBeginEditingNotification, true),
            (UITextField.textDidEndEditingNotification, false),
            (UITextView.textDidBeginEditingNotification, true),
            (UITextView.textDidEndEditingNotification, false),
        ]
        observers = pairs.map { name, begins in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let field = note.object as AnyObject? else { return }
                MainActor.assumeIsolated {
                    if begins { self?.began(field) } else { self?.ended(field) }
                }
            }
        }
    }

    private func update() {
        let editing = !active.isEmpty
        if isEditing != editing { isEditing = editing }
    }
}
#endif

// MARK: - The commands

/// The menu bar: File's New and Print, Edit's Undo and Redo, Format, Draw and
/// View. Every shortcut is a button here, built from `NoteShortcut`, so holding
/// ⌘ on the iPad lists them and the menu bar shows them.
struct NoteCommands: Commands {
    @FocusedValue(\.windowActions) private var window

#if canImport(UIKit)
    @FocusedValue(\.openNote) private var note
    private let typing = TextInputActivity.shared
#endif

    var body: some Commands {
        // New Window is the default ⌘N, and the app's own idea of new is a note.
        CommandGroup(replacing: .newItem) {
            Button(NoteShortcut.newNote.title) { window?.newNote() }
                .keyboardShortcut(.newNote)
                .disabled(window == nil)
            Button(NoteShortcut.newFolder.title) { window?.newFolder() }
                .keyboardShortcut(.newFolder)
                .disabled(window == nil)
        }

        CommandGroup(replacing: .sidebar) {
            Button(NoteShortcut.noteList.title) { window?.toggleNoteList() }
                .keyboardShortcut(.noteList)
                .disabled(window == nil)
            Button(NoteShortcut.searchNotes.title) { window?.searchNotes() }
                .keyboardShortcut(.searchNotes)
                .disabled(window == nil)
            Button(NoteShortcut.home.title) { window?.goHome() }
                .keyboardShortcut(.home)
                .disabled(window == nil)
        }

#if canImport(UIKit)
        noteCommands
#endif
    }

#if canImport(UIKit)
    @CommandsBuilder
    private var noteCommands: some Commands {
        CommandGroup(replacing: .printItem) {
            Button(NoteShortcut.print.title) { note?.printNote() }
                .keyboardShortcut(.print)
                .disabled(note == nil)
        }

        // The system's Undo reaches only a first responder with an undo
        // manager, and in ink mode there is none. See `undoFromKeyboard`.
        CommandGroup(replacing: .undoRedo) {
            Button(NoteShortcut.undo.title) { undo() }
                .keyboardShortcut(.undo)
            Button(NoteShortcut.redo.title) { redo() }
                .keyboardShortcut(.redo)
        }

        CommandGroup(replacing: .textFormatting) {
            let editor = note?.editor
            let canFormat = editor?.mode == .text && editor?.isTextLocked == false

            Group {
                Button(NoteShortcut.bold.title) { editor?.toggle(.bold) }
                    .keyboardShortcut(.bold)
                Button(NoteShortcut.italic.title) { editor?.toggle(.italic) }
                    .keyboardShortcut(.italic)
                Button(NoteShortcut.inlineCode.title) { editor?.toggle(.code) }
                    .keyboardShortcut(.inlineCode)
                Button(NoteShortcut.strikethrough.title) { editor?.toggle(.strikethrough) }
                    .keyboardShortcut(.strikethrough)
                Divider()
                Button(NoteShortcut.heading1.title) { editor?.setHeading(level: 1) }
                    .keyboardShortcut(.heading1)
                Button(NoteShortcut.heading2.title) { editor?.setHeading(level: 2) }
                    .keyboardShortcut(.heading2)
                Button(NoteShortcut.heading3.title) { editor?.setHeading(level: 3) }
                    .keyboardShortcut(.heading3)
                Button(NoteShortcut.body.title) { editor?.setHeading(level: 0) }
                    .keyboardShortcut(.body)
                Divider()
                Button(NoteShortcut.bulletedList.title) { editor?.toggleBullet() }
                    .keyboardShortcut(.bulletedList)
                Button(NoteShortcut.codeBlock.title) { editor?.insertCodeBlockInLastLanguage() }
                    .keyboardShortcut(.codeBlock)
            }
            .disabled(!canFormat)

            Divider()

            Group {
                Button(NoteShortcut.runBlock.title) { editor?.runBlockAtCaret?() }
                    .keyboardShortcut(.runBlock)
                Button(NoteShortcut.copyBlock.title) { editor?.copyBlockAtCaret?() }
                    .keyboardShortcut(.copyBlock)
            }
            .disabled(editor?.mode != .text)
        }

        CommandMenu("Draw") {
            let editor = note?.editor
            let inks = editor?.mode == .ink && !typing.isEditing && window?.isCovered != true

            Button(NoteShortcut.toggleMode.title) { editor?.toggleMode() }
                .keyboardShortcut(.toggleMode)
                .disabled(editor == nil)

            Divider()

            // Bare keys: off whenever a field could be taking them as typing.
            Group {
                Button(NoteShortcut.pen.title) { editor?.selectTool(.pen) }
                    .keyboardShortcut(.pen)
                Button(NoteShortcut.highlighter.title) { editor?.selectTool(.highlighter) }
                    .keyboardShortcut(.highlighter)
                Button(NoteShortcut.eraser.title) { editor?.selectTool(.eraser) }
                    .keyboardShortcut(.eraser)
                Button(NoteShortcut.lasso.title) { editor?.selectTool(.lasso) }
                    .keyboardShortcut(.lasso)
                Divider()
                Button(NoteShortcut.thinner.title) { editor?.stepWidth(by: -1) }
                    .keyboardShortcut(.thinner)
                Button(NoteShortcut.thicker.title) { editor?.stepWidth(by: 1) }
                    .keyboardShortcut(.thicker)
            }
            .disabled(!inks)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach([PageViewMode.seamless, .compressed, .print], id: \.self) { mode in
                Toggle(isOn: Binding(
                    get: { note?.viewMode.wrappedValue == mode },
                    set: { _ in note?.viewMode.wrappedValue = mode }
                )) {
                    Text(mode.title)
                }
                .keyboardShortcut(mode.shortcut)
                .disabled(note == nil)
            }
        }
    }

    private func undo() {
        if let note {
            note.editor.undoFromKeyboard()
        } else {
            UIResponder.currentFirstResponder?.undoManager?.undo()
        }
    }

    private func redo() {
        if let note {
            note.editor.redoFromKeyboard()
        } else {
            UIResponder.currentFirstResponder?.undoManager?.redo()
        }
    }
#endif
}

extension PageViewMode {
    /// ⌘1, ⌘2 and ⌘3.
    var shortcut: NoteShortcut {
        switch self {
        case .seamless:   .seamless
        case .compressed: .compressed
        case .print:      .printLayout
        }
    }
}
