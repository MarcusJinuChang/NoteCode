//
//  CodeBlockPageBreakTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

/// A code block that meets a page break, laid out by TextKit for real.
///
/// TextKit keeps a fragment's frame starting where its paragraph began and
/// pushes the line down inside it, so anything positioned from the frame lands
/// in the break. On the simulator that painted a code panel across the gap
/// between two sheets.
@Suite("Code blocks at page breaks")
@MainActor
struct CodeBlockPageBreakTests {

    final class Box { var value = "" }

    @MainActor
    final class Rig {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1400, height: 1400))
        let coordinator: DocumentTextView.Coordinator
        let page: PageView
        let layout = PageLayout(mode: .print)

        init(prose lines: Int) {
            let box = Box()
            coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
            let text = (0..<lines).map { "Line \($0): the loop invariant holds gjpqy." }.joined(separator: "\n")
                + "\n```cpp\nint query(gap g) {\n    return g.jump();\n}\n```\nAfter."

            let textView = DocumentTextView.makeConfiguredTextView()
            textView.delegate = coordinator
            textView.textLayoutManager?.delegate = coordinator
            coordinator.attachOverlay(to: textView)
            textView.text = text
            coordinator.invalidateStyling()
            coordinator.restyle(textView)

            page = PageView(textView: textView)
            page.pageLayout = layout
            page.frame = CGRect(x: 0, y: 0, width: 880, height: 1100)
            window.addSubview(page)
            window.makeKeyAndVisible()
            layOut()
        }

        func layOut() {
            for _ in 0..<3 {
                page.setNeedsLayout()
                page.layoutIfNeeded()
                page.textView.setNeedsLayout()
                page.textView.layoutIfNeeded()
            }
        }

        var bandRects: [CGRect] {
            page.textView.textContainer.exclusionPaths.map(\.bounds)
        }

        /// The code block's fragments, in container coordinates.
        var codeFragments: [CodeBlockLayoutFragment] {
            guard let manager = page.textView.textLayoutManager,
                  let content = manager.textContentManager
            else { return [] }
            var found: [CodeBlockLayoutFragment] = []
            manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
                if let code = fragment as? CodeBlockLayoutFragment { found.append(code) }
                return true
            }
            return found
        }
    }

    /// Adds prose until a code line is pushed across the first page break
    /// with its fragment frame starting above it — the case that went wrong.
    static func rigWithCodeAcrossBreak(fenceFirst: Bool) -> Rig? {
        for lines in 30...60 {
            let rig = Rig(prose: lines)
            let bands = rig.bandRects
            guard let band = bands.first else { continue }

            let candidates = fenceFirst ? Array(rig.codeFragments.prefix(1)) : Array(rig.codeFragments.dropFirst())
            let straddles = candidates.contains { fragment in
                let frame = fragment.layoutFragmentFrame
                return frame.minY < band.minY && frame.maxY > band.maxY
            }
            if straddles { return rig }
        }
        return nil
    }

    @Test("A code line pushed onto the next page has no panel in the break", arguments: [true, false])
    func panelStaysOffTheBreak(fenceFirst: Bool) throws {
        let rig = try #require(Self.rigWithCodeAcrossBreak(fenceFirst: fenceFirst))
        let breaks = rig.bandRects.map { $0.minY...$0.maxY }

        for fragment in rig.codeFragments {
            let frame = fragment.layoutFragmentFrame
            let lines = fragment.textLineFragments.map {
                (frame.minY + $0.typographicBounds.minY)...(frame.minY + $0.typographicBounds.maxY)
            }
            let runs = CodeBlockLayoutFragment.panelRuns(frame: frame, lines: lines, breaks: breaks, position: fragment.position)

            for run in runs {
                for band in rig.bandRects {
                    #expect(run.bottom <= band.minY + 0.5 || run.top >= band.maxY - 0.5,
                            "panel \(run.top)...\(run.bottom) crosses the break \(band.minY)...\(band.maxY)")
                }
            }
        }
    }

    @Test("A code block that starts a new page puts its buttons on the page, not in the break")
    func buttonsStayOffTheBreak() throws {
        let rig = try #require(Self.rigWithCodeAcrossBreak(fenceFirst: true))
        let textView = rig.page.textView
        let band = try #require(rig.bandRects.first).offsetBy(dx: 0, dy: textView.textContainerInset.top)

        // Bring the break into view so the overlay places the bar.
        textView.contentOffset.y = max(band.minY - 300, 0)
        rig.layOut()

        let bars = textView.subviews.compactMap { $0 as? CodeBlockActionBar }.filter { !$0.isHidden }
        let bar = try #require(bars.first)
        #expect(!bar.frame.intersects(band), "bar \(bar.frame) sits in the break \(band)")
        #expect(bar.frame.minY >= band.maxY - CodeBlockActionBar.buttonSide)
    }
}

#endif
