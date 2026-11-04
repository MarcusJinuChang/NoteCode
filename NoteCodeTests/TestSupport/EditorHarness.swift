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
    /// How much of `DocumentTextView.makeUIView` the text view gets.
    enum Wiring {
        /// No Coordinator: the editor alone drives the text view, so nothing
        /// restyles it or reports the caret (the text size tests).
        case none
        /// A Coordinator as the text view's delegate that knows the editor,
        /// and nothing else (the note editor tests).
        case delegate
        /// Everything, in `makeUIView`'s order: the text view is styled,
        /// with its overlay, before the page exists.
        case full
    }

    var stored: String
    let window: UIWindow
    let textView = DocumentTextView.makeConfiguredTextView()
    let editor = NoteEditor()
    private(set) var page: PageView!
    var coordinator: DocumentTextView.Coordinator!
    var canvas: DrawingCanvas { page.canvas }
    /// What the editor handed back to be stored, on each text size change.
    private(set) var committedTextSizes: [Int?] = []

    /// - Parameters:
    ///   - caretMarker: where it appears in `text`, it is taken out and the
    ///     caret put there.
    ///   - window: the window's size; the page is `area`, or fills the
    ///     window when that is nil.
    ///   - lockedFirst: locks the text before the editor has a text view,
    ///     the way a locked note's page opens.
    init(
        _ text: String = TestFixtures.codeFenceNote,
        wiring: Wiring = .full,
        caretMarker: String? = nil,
        style: UIUserInterfaceStyle = .light,
        layout: PageLayout = PageLayout(),
        showMarkdown: ShowMarkdown = .whileEditing,
        rendersMarkdown: Bool = false,
        window size: CGSize = CGSize(width: 1100, height: 1400),
        area: CGSize? = CGSize(width: 872, height: 1200),
        lockedFirst: Bool = false
    ) {
        let caret = caretMarker.map { (text as NSString).range(of: $0).location }
        stored = caretMarker.map { text.replacingOccurrences(of: $0, with: "") } ?? text
        window = makeTestWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = style

        switch wiring {
        case .none:
            page = PageView(textView: textView)
            textView.text = stored
        case .delegate:
            page = PageView(textView: textView)
            coordinator = makeCoordinator()
            coordinator.editor = editor
            textView.delegate = coordinator
            textView.text = stored
        case .full:
            coordinator = makeCoordinator()
            textView.delegate = coordinator
            textView.textLayoutManager?.delegate = coordinator
            coordinator.observeEdits(of: textView)
            coordinator.attachOverlay(to: textView)
            coordinator.setRendersMarkdown(rendersMarkdown, in: textView)
            textView.text = stored
            coordinator.invalidateStyling()
            coordinator.restyle(textView)
            coordinator.showMarkdown = showMarkdown
            coordinator.connect(editor, to: textView)
            page = PageView(textView: textView)
            // As in the app, the bars sit beneath the ink canvas.
            coordinator.keepBars(under: page.canvas)
        }

        page.pageLayout = layout
        page.frame = CGRect(origin: .zero, size: area ?? size)
        window.addSubview(page)
        window.makeKeyAndVisible()
        if lockedFirst {
            editor.setTextLocked(true)
        }
        editor.attach(textView, canvas: page.canvas, page: page)
        editor.commitTextSize = { [unowned self] size in
            committedTextSizes.append(size)
        }
        layOut()
        if let caret {
            textView.selectedRange = NSRange(location: caret, length: 0)
            coordinator?.refreshCaretFormatting(in: textView)
        }
    }

    private func makeCoordinator() -> DocumentTextView.Coordinator {
        DocumentTextView.Coordinator(
            text: Binding(get: { [unowned self] in stored }, set: { [unowned self] in stored = $0 })
        )
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

    /// Types `text` at `offset` the way the keyboard does, including the
    /// delegate call that restyles and makes bars for new blocks.
    func type(_ text: String, at offset: Int) {
        textView.selectedRange = NSRange(location: offset, length: 0)
        textView.insertText(text)
        coordinator.textViewDidChange(textView)
        page.layoutIfNeeded()
        textView.layoutIfNeeded()
    }

    func settle() async throws {
        textView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        textView.layoutIfNeeded()
    }

    /// Each tap of a chip is its own turn of the run loop in the app, and
    /// so its own undo step: UIKit closes an undo group at the end of the
    /// turn. A test makes its edits back to back, in one turn, and a
    /// single undo would take them all.
    func nextTap() async {
        try? await Task.sleep(for: .milliseconds(30))
    }

    /// Long enough for a shortened `NoteEditor.settleDelay` (20ms) to pass.
    func wait() async {
        try? await Task.sleep(for: .milliseconds(120))
    }

    // MARK: What a reader sees

    var text: String { textView.text ?? "" }

    var source: NSString { textView.textStorage.string as NSString }

    /// The block the caret is in, as the text options row shows it.
    var caretBlock: MarkdownFormatting.CaretFormatting.Block { editor.caretFormatting.block }

    /// The text view's scrolling pans, whose touches the mode decides.
    var pans: [UIPanGestureRecognizer] { [textView.panGestureRecognizer] }

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

    /// The action bars a reader can see: shown, and inside the visible part
    /// of the text view.
    var visibleBars: [CodeBlockActionBar] {
        let visible = CGRect(origin: textView.contentOffset, size: textView.bounds.size)
        return textView.subviews
            .compactMap { $0 as? CodeBlockActionBar }
            .filter { !$0.isHidden && visible.contains($0.frame) }
    }
}

#endif
