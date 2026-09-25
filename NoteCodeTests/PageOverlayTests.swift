//
//  PageOverlayTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Action bars on the page")
@MainActor
struct PageOverlayTests {

    /// Wired in the same order `DocumentTextView.makeUIView` wires it: the
    /// text view is styled, with its overlay, before the page exists.
    @MainActor
    private final class Harness {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 1400))
        let coordinator: DocumentTextView.Coordinator
        let page: PageView

        init(_ text: String, area: CGSize) {
            let box = Box()
            coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))

            let textView = DocumentTextView.makeConfiguredTextView()
            textView.delegate = coordinator
            textView.textLayoutManager?.delegate = coordinator
            coordinator.attachOverlay(to: textView)
            textView.text = text
            coordinator.invalidateStyling()
            coordinator.restyle(textView)

            page = PageView(textView: textView)
            coordinator.keepBars(under: page.canvas)
            page.frame = CGRect(origin: .zero, size: area)
            window.addSubview(page)
            window.makeKeyAndVisible()
            page.layoutIfNeeded()
            textView.layoutIfNeeded()
        }

        final class Box { var value = "" }

        /// Types `text` at `offset` the way the keyboard does, including the
        /// delegate call that restyles and makes bars for new blocks.
        func type(_ text: String, at offset: Int) {
            let textView = page.textView
            textView.selectedRange = NSRange(location: offset, length: 0)
            textView.insertText(text)
            coordinator.textViewDidChange(textView)
            page.layoutIfNeeded()
            textView.layoutIfNeeded()
        }

        var visibleBars: [CodeBlockActionBar] {
            let textView = page.textView
            let visible = CGRect(origin: textView.contentOffset, size: textView.bounds.size)
            return textView.subviews
                .compactMap { $0 as? CodeBlockActionBar }
                .filter { !$0.isHidden && visible.contains($0.frame) }
        }
    }

    private static let note = "Typography check\n```cpp\nint query(gap g) { return g; }\n```\nAfter the block."

    @Test("A code block's run and copy buttons are showing as soon as the note opens", arguments: [
        CGSize(width: 872, height: 1200),   // 13-inch portrait, at the 1.25 ceiling
        CGSize(width: 682, height: 1000),   // 11-inch portrait, below 1x
    ])
    func barsShowOnOpen(area: CGSize) {
        let harness = Harness(Self.note, area: area)

        #expect(harness.visibleBars.count == 1)
    }

    /// Typing lays the text out with no layout pass of the text view, which
    /// was the only thing that placed bars: a block just typed had a bar,
    /// hidden, with no frame, until something else laid the text view out.
    @Test("A code block typed into the note gets its buttons straight away")
    func typedBlockGetsItsBar() {
        let harness = Harness(Self.note, area: CGSize(width: 872, height: 1200))
        harness.type("\n```python\nprint(1)\n```", at: (Self.note as NSString).length)

        #expect(harness.visibleBars.count == 2)
    }

    /// Exactly one layer takes touches: in draw mode the canvas, over every
    /// bar, whether the bar was made as the note opened or for a block typed
    /// afterwards; in text mode the bars. Bars made later used to land on top
    /// of the canvas.
    @Test("In draw mode the canvas takes touches on every bar; in text mode the bars do")
    func barsUnderTheCanvas() throws {
        let harness = Harness(Self.note, area: CGSize(width: 872, height: 1200))
        let secondBlock = "\n```python\nprint(1)\n```"
        harness.type(secondBlock, at: (Self.note as NSString).length)
        let bars = harness.visibleBars
        try #require(bars.count == 2)

        func hit(_ bar: CodeBlockActionBar) -> UIView? {
            let center = bar.convert(CGPoint(x: bar.bounds.midX, y: bar.bounds.midY), to: harness.window)
            return harness.window.hitTest(center, with: nil)
        }

        harness.page.canvas.isUserInteractionEnabled = true
        for bar in bars {
            let view = try #require(hit(bar))
            #expect(view.isDescendant(of: harness.page.canvas), "draw mode: \(type(of: view)) took the touch")
        }

        harness.page.canvas.isUserInteractionEnabled = false
        for bar in bars {
            let view = try #require(hit(bar))
            #expect(view.isDescendant(of: bar), "text mode: \(type(of: view)) took the touch")
        }
    }

    @Test("The buttons sit at the panel's right edge, in page points")
    func barsAtPanelEdge() throws {
        let harness = Harness(Self.note, area: CGSize(width: 872, height: 1200))
        let textView = harness.page.textView
        let panelRight = textView.bounds.width - textView.textContainerInset.right

        let bar = try #require(harness.visibleBars.first)
        #expect(abs(bar.frame.maxX - (panelRight - CodeBlockActionBar.margin)) < 0.5)
    }
}

#endif
