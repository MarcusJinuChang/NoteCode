//
//  MidEditRenderTests.swift
//  NoteCodeTests
//
//  SwiftUI rendering the note while UIKit is still inside a keystroke.
//
//  `insertText` changes the storage and the selection before it tells the
//  delegate the text changed, so for a moment the storage is ahead of the
//  note's binding. A render in that moment (the keyboard reloading as the
//  caret crosses into inline code moved its frame, on the simulator) ran
//  `updateUIView`, which pushed the stale binding back into the text view:
//  the character just typed was wiped outside UIKit's typing undo, and the
//  next Undo replaced a range past the end of the text and aborted the app
//  (NSRangeException from NSMutableRLEArray, device pass format-4).
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("A render in the middle of a keystroke", .tags(.editor))
@MainActor
struct MidEditRenderTests {

    @Observable
    final class Note {
        var text = ""
        /// Read by the host's body, so bumping it renders the editor again.
        var renders = 0
    }

    struct Host: View {
        let note: Note
        var body: some View {
            let _ = note.renders
            DocumentTextView(text: Binding(get: { note.text }, set: { note.text = $0 }))
        }
    }

    /// Sits in front of the coordinator as the text view's delegate and,
    /// once the coordinator has seen a selection change, makes SwiftUI render
    /// the note there and then, as the keyboard's frame change did.
    final class RenderOnSelection: NSObject, UITextViewDelegate {
        let coordinator: DocumentTextView.Coordinator
        let render: () -> Void

        init(coordinator: DocumentTextView.Coordinator, render: @escaping () -> Void) {
            self.coordinator = coordinator
            self.render = render
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || coordinator.responds(to: selector)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            coordinator.responds(to: selector) ? coordinator : super.forwardingTarget(for: selector)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            coordinator.textViewDidChangeSelection(textView)
            render()
        }
    }

    private static func findTextView(in view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for sub in view.subviews { if let found = findTextView(in: sub) { return found } }
        return nil
    }

    /// The note in a window, its text view, and a delegate that renders
    /// inside every keystroke.
    private struct Hosted {
        let note: Note
        let window: UIWindow
        let textView: UITextView
        let coordinator: DocumentTextView.Coordinator
        let delegate: RenderOnSelection
        var rendersInsideEdits: () -> Int

        /// Lets SwiftUI render what the note now holds.
        func render() {
            let view = window.rootViewController?.view
            view?.setNeedsLayout()
            view?.layoutIfNeeded()
        }

        func close() {
            textView.delegate = coordinator
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func host(_ text: String = "") throws -> Hosted {
        let note = Note()
        note.text = text
        let host = UIHostingController(rootView: Host(note: note))
        let window = makeSceneLessTestWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 1400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        let textView = try #require(Self.findTextView(in: window))
        let coordinator = try #require(textView.delegate as? DocumentTextView.Coordinator)
        final class Count { var value = 0 }
        let count = Count()
        let delegate = RenderOnSelection(coordinator: coordinator) {
            note.renders += 1
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            count.value += 1
        }
        textView.delegate = delegate
        _ = textView.becomeFirstResponder()
        return Hosted(
            note: note, window: window, textView: textView, coordinator: coordinator,
            delegate: delegate, rendersInsideEdits: { count.value }
        )
    }

    /// One key at a time, as the keyboard sends them.
    private func type(_ text: String, in textView: UITextView) {
        for key in text { textView.insertText(String(key)) }
    }

    @Test("Typing inline code with a render inside each keystroke keeps every character, and Undo undoes it")
    func renderInsideKeystroke() throws {
        let hosted = try host()
        defer { hosted.close() }
        let textView = hosted.textView

        type("a `code` b", in: textView)

        #expect(hosted.rendersInsideEdits() > 0)
        #expect(textView.text == "a `code` b")
        #expect(hosted.note.text == "a `code` b")

        // Undo reads UIKit's typing record against the storage; with a
        // character wiped behind its back it aborts the test run, so only
        // try it when the text survived.
        guard textView.text == "a `code` b" else { return }
        let undo = try #require(textView.undoManager)
        #expect(undo.canUndo)
        while undo.canUndo { undo.undo() }
        #expect(textView.text == "")
        #expect(hosted.note.text == "")
    }

    @Test("A fence typed, a paste and an edit inside it, all with renders inside, keep their text and undo cleanly")
    func fencePasteAndMidFenceEdit() throws {
        let hosted = try host()
        defer { hosted.close() }
        let textView = hosted.textView

        type("Notes\n```cpp\nint x;\n```\nafter", in: textView)
        let typed = "Notes\n```cpp\nint x;\n```\nafter"
        #expect(textView.text == typed)
        #expect(hosted.note.text == typed)
        // The offsets below are found in the text, and read nothing without it.
        guard textView.text == typed else { return }

        // A paste inside the fence: one replacement, as the edit menu makes.
        let inside = (typed as NSString).range(of: "int x;").location + "int x;".count
        textView.selectedRange = NSRange(location: inside, length: 0)
        if let range = textView.selectedTextRange {
            textView.replace(range, withText: "\nint y = x + 1;")
        }
        // And an edit in the middle of the fence's first line.
        let middle = (textView.text as NSString).range(of: "int x").location + 5
        textView.selectedRange = NSRange(location: middle, length: 0)
        type("yz", in: textView)

        let expected = "Notes\n```cpp\nint xyz;\nint y = x + 1;\n```\nafter"
        #expect(textView.text == expected)
        #expect(hosted.note.text == expected)

        guard textView.text == expected else { return }
        let undo = try #require(textView.undoManager)
        while undo.canUndo { undo.undo() }
        #expect(textView.text == "")
        #expect(hosted.note.text == "")
    }

    @Test("Text the note gets from outside still reaches the text view")
    func outsideChangeStillPushed() throws {
        let hosted = try host("before")
        defer { hosted.close() }
        #expect(hosted.textView.text == "before")

        type(" typed", in: hosted.textView)
        #expect(hosted.note.text == "before typed")

        hosted.note.text = "replaced from outside"
        hosted.render()
        #expect(hosted.textView.text == "replaced from outside")

        // And back to what it was synced at before, which is a change too.
        // The outside value above has already moved `syncedText` on, so this
        // is not a no-op: it checks the comparison is with the last sync, not
        // with the first.
        hosted.note.text = "before typed"
        hosted.render()
        #expect(hosted.textView.text == "before typed")
    }
}

#endif
