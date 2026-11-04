//
//  NotePageChromeTests.swift
//  NoteCodeTests
//
//  The note page's small decisions: the edit menu's order, where the share
//  sheet points and what the file is called, the outline's height.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Note page chrome")
@MainActor
struct NotePageChromeTests {

    // MARK: Edit menu

    private func command(_ title: String, _ action: Selector) -> UICommand {
        UICommand(title: title, action: action)
    }

    private func titles(_ elements: [UIMenuElement]) -> [String] {
        elements.flatMap { element -> [String] in
            if let menu = element as? UIMenu { return titles(menu.children) }
            return [element.title]
        }
    }

    @Test("Cut, Copy and Paste lead the edit menu, ahead of the app's rows")
    func pasteLeads() {
        let ours = UIMenu(options: .displayInline, children: [
            UIAction(title: "Bold") { _ in }, UIAction(title: "Italic") { _ in },
        ])
        let system: [UIMenuElement] = [
            UIMenu(options: .displayInline, children: [
                command("Select", #selector(UIResponder.select(_:))),
                command("Select All", #selector(UIResponder.selectAll(_:))),
            ]),
            UIMenu(options: .displayInline, children: [
                command("Cut", #selector(UIResponderStandardEditActions.cut(_:))),
                command("Copy", #selector(UIResponderStandardEditActions.copy(_:))),
                command("Paste", #selector(UIResponderStandardEditActions.paste(_:))),
            ]),
            command("Look Up", #selector(UIResponder.select(_:))),
        ]
        let ordered = EditMenuOrder.order(ours: [ours], system: system)
        #expect(titles(ordered) == ["Cut", "Copy", "Paste", "Bold", "Italic", "Select", "Select All", "Look Up"])
        #expect(ordered.count == 6, "the emptied group is gone, not left as an empty menu")
    }

    @Test("A menu with no Paste (nothing to paste) is the app's rows, then the system's")
    func noPaste() {
        let ours = UIAction(title: "Bold") { _ in }
        let system: [UIMenuElement] = [command("Select All", #selector(UIResponder.selectAll(_:)))]
        #expect(titles(EditMenuOrder.order(ours: [ours], system: system)) == ["Bold", "Select All"])
    }

    // MARK: Share

    @Test("The share sheet points at the button, in the window")
    func pointsAtButton() {
        let window = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        let button = CGRect(x: 1250, y: 14, width: 44, height: 36)
        #expect(SharePopover.sourceRect(button: button, in: window) == button)
    }

    @Test("A button with no size, or off the window, never sends the sheet to the top-left corner")
    func neverTopLeft() {
        let window = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        for button in [CGRect.zero, CGRect(x: 0, y: 0, width: 0, height: 0), CGRect(x: -400, y: -400, width: 44, height: 36)] {
            let rect = SharePopover.sourceRect(button: button, in: window)
            #expect(rect.midX > window.midX && rect.midY < window.midY, "\(button) gave \(rect)")
        }
    }

    @Test("The PDF is titled for the note, or its first line when it has no title")
    func documentTitle() {
        #expect(SharePopover.documentTitle("Graphs", text: "# Other") == "Graphs")
        #expect(SharePopover.documentTitle("  ", text: "\n## Dijkstra notes\nbody") == "Dijkstra notes")
        #expect(SharePopover.documentTitle("", text: "```cpp\nint x;\n```\nbody") == "int x;")
        #expect(SharePopover.documentTitle("", text: "") == "")
        #expect(NotePDF.fileName(for: SharePopover.documentTitle("", text: "")) == "Untitled.pdf")
        #expect(NotePDF.fileName(for: SharePopover.documentTitle("", text: "# Heaps")) == "Heaps.pdf")
    }

    // MARK: Outline

    @Test("The outline is as tall as its rows, with no empty row under the last")
    func outlineHeight() {
        #expect(NoteOutlineView.height(forRows: 5) == 5 * NoteOutlineView.rowHeight)
        #expect(NoteOutlineView.height(forRows: 1) == 3 * NoteOutlineView.rowHeight)
        #expect(NoteOutlineView.height(forRows: 500) == 420)
    }
}

#endif
