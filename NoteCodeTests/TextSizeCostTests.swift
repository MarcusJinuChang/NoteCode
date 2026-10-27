//
//  TextSizeCostTests.swift
//  NoteCodeTests
//
//  T1 of the 1.0 plan: a size change is instant. The note's text size is a
//  highly used action, so what it costs is measured, not guessed.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Text size: what a change costs", .serialized)
@MainActor
struct TextSizeCostTests {

    /// About 250 lines: headings, prose, lists and a code block in every
    /// fifth section.
    static let note: String = (0..<25).map { n in
        var section = "## Section \(n)\n"
        section += "Some **bold** prose with `inline code`, a [link](https://example.com) and enough words to wrap onto a second line of the page.\n"
        section += "- first item\n- second item\n- third item\n\n"
        section += "```cpp\nint main() {\n    for (int i = 0; i < \(n); i++) {\n        std::cout << i << std::endl;\n    }\n    return 0;\n}\n```\n\n"
        return section
    }.joined()

    /// Milliseconds from the call to the end of `reflow`, which is what the
    /// reader waits for before the first frame, split into the restyle and
    /// the layout that follows it.
    static func change(to size: Int, _ opened: ReopenTests.Opened) -> (restyle: Double, layout: Double) {
        let page = opened.page
        var restyle = 0.0
        let start = ContinuousClock.now
        page.reflow {
            let began = ContinuousClock.now
            opened.coordinator.setTypography(NoteTypography(bodySize: size), in: page.textView)
            restyle = Double((ContinuousClock.now - began).components.attoseconds) / 1e15
        }
        let total = Double((ContinuousClock.now - start).components.attoseconds) / 1e15
        return (restyle, total - restyle)
    }

    @Test("A size change on a 250-line note reaches its first frame within budget")
    func firstFrame() async throws {
        let opened = await ReopenTests.open(resumingAtPage: nil, layout: PageLayout())
        opened.page.textView.text = Self.note
        opened.coordinator.invalidateStyling()
        opened.coordinator.restyle(opened.page.textView)
        await ReopenTests.layOut(opened.page, over: 0.8)

        var report: [String] = []
        var worst = 0.0
        for size in [23, 14, 21, 17, 23, 15] {
            let (restyle, layout) = Self.change(to: size, opened)
            worst = max(worst, restyle + layout)
            report.append("\(size)pt: restyle \(Int(restyle))ms, layout \(Int(layout))ms")
            await ReopenTests.layOut(opened.page, over: 0.4)
        }
        print("TEXTSIZE-COST lines=\(Self.note.split(separator: "\n", omittingEmptySubsequences: false).count)\n" + report.joined(separator: "\n"))
        // Measured 26 Oct on the simulator: 55 to 100ms, four fifths of it layout,
        // against the plan's 100ms. Loose, like `typingCost`: this catches a
        // restyle that lays the whole note out twice, not noise.
        #expect(worst < 200, "a size change took \(Int(worst))ms to its first frame")
        withExtendedLifetime(opened) {}
    }
}

#endif
