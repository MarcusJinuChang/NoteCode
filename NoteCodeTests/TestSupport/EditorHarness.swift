//
//  EditorHarness.swift
//  NoteCodeTests
//
//  A text view wired the way `DocumentTextView` wires it, in its page, in a
//  window, with the note's stored text behind a binding the test can read.
//

#if canImport(UIKit)

import SwiftUI
import UIKit
@testable import NoteCode

@MainActor
final class EditorHarness {
    var stored: String
    let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 1400))
    let textView = DocumentTextView.makeConfiguredTextView()
    let editor = NoteEditor()
    let page: PageView
    var coordinator: DocumentTextView.Coordinator!

    init(
        _ text: String = TestFixtures.codeFenceNote,
        style: UIUserInterfaceStyle = .light,
        layout: PageLayout = PageLayout(),
        showMarkdown: ShowMarkdown = .whileEditing
    ) {
        stored = text
        page = PageView(textView: textView)
        window.overrideUserInterfaceStyle = style
        coordinator = DocumentTextView.Coordinator(
            text: Binding(get: { [unowned self] in stored }, set: { [unowned self] in stored = $0 })
        )
        coordinator.showMarkdown = showMarkdown
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        coordinator.observeEdits(of: textView)
        coordinator.attachOverlay(to: textView)
        // As in the app, the bars sit beneath the ink canvas.
        coordinator.keepBars(under: page.canvas)
        textView.text = text
        coordinator.invalidateStyling()
        coordinator.restyle(textView)

        page.pageLayout = layout
        page.frame = CGRect(x: 0, y: 0, width: 872, height: 1200)
        window.addSubview(page)
        window.makeKeyAndVisible()
        editor.attach(textView, canvas: page.canvas, page: page)
        coordinator.connect(editor, to: textView)
        layOut()
    }

    func layOut() {
        for _ in 0..<3 {
            page.setNeedsLayout()
            page.layoutIfNeeded()
            textView.setNeedsLayout()
            textView.layoutIfNeeded()
        }
    }

    // MARK: What a reader does

    /// Puts the caret (or a selection) where a tap or a drag would, and
    /// lets the redraws it asks for happen.
    func select(_ range: NSRange) async throws {
        textView.selectedRange = range
        coordinator.textViewDidChangeSelection(textView)
        try await settle()
    }

    func caret(at offset: Int) async throws {
        try await select(NSRange(location: offset, length: 0))
    }

    func settle() async throws {
        textView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        textView.layoutIfNeeded()
    }

    // MARK: What a reader sees

    var source: NSString { textView.textStorage.string as NSString }

    func offset(of text: String, backwards: Bool = false) -> Int {
        source.range(of: text, options: backwards ? .backwards : []).location
    }

    /// Where a stretch of text is, in the text view's coordinates.
    func rect(of text: String, backwards: Bool = false) -> CGRect {
        let range = source.range(of: text, options: backwards ? .backwards : [])
        let start = textView.position(from: textView.beginningOfDocument, offset: range.location)!
        let end = textView.position(from: start, offset: range.length)!
        return textView.firstRect(for: textView.textRange(from: start, to: end)!)
    }

    // MARK: Code blocks

    /// The part of a line's rect that is surely on the panel: `firstRect`
    /// is a line tall, and a block's end lines have the panel's rounded
    /// corner and its gap to the next line inside that. Clear of the
    /// ring's edge too, which the first pixel mustn't land on.
    func interior(of rect: CGRect) -> CGRect {
        rect.insetBy(dx: 6, dy: 5)
    }

    /// The same for the opening fence's line, whose top is the gap above
    /// the panel (`CodeBlockRoom`): its header.
    func headerInterior(of rect: CGRect) -> CGRect {
        interior(of: CodeBlockRoom.header(ofFenceLine: rect))
    }

    /// The same for the closing fence's line, whose bottom is the gap
    /// below the panel: its footer, which is shallow, so inset less.
    /// `firstRect` reaches half a point past the line, so the footer's
    /// bottom is the panel's edge less that, and 2pt clears it.
    func footerInterior(of rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - CodeBlockRoom.gapBelow)
            .insetBy(dx: 6, dy: 2)
    }

    var languageButton: CodeBlockLanguageButton? {
        textView.subviews.compactMap { $0 as? CodeBlockLanguageButton }.first
    }
}

#endif
