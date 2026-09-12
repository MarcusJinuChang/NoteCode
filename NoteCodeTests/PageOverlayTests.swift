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
            page.frame = CGRect(origin: .zero, size: area)
            window.addSubview(page)
            window.makeKeyAndVisible()
            page.layoutIfNeeded()
            textView.layoutIfNeeded()
        }

        final class Box { var value = "" }

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
