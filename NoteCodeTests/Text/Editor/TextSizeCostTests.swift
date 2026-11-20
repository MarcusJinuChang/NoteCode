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

@Suite("Text size: what a change costs", .serialized, .tags(.editor, .perf), .timeLimit(.minutes(1)))
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
        // `ReopenTests.open` does not watch the storage, so the style session
        // would keep the snapshot of the note it opened and the restyle below
        // would index the new text with the old note's ranges.
        opened.coordinator.observeEdits(of: opened.page.textView)
        opened.page.textView.text = Self.note
        opened.coordinator.invalidateStyling()
        opened.coordinator.restyle(opened.page.textView)
        await ReopenTests.layOut(opened.page)

        var report: [String] = []
        var totals: [Double] = []
        for size in [23, 14, 21, 17, 23, 15] {
            let (restyle, layout) = Self.change(to: size, opened)
            totals.append(restyle + layout)
            report.append("\(size)pt: restyle \(Int(restyle))ms, layout \(Int(layout))ms")
            await ReopenTests.layOut(opened.page)
        }
        // The row is the median of the six changes, not the worst (D21): the
        // worst is one change, and one stall of the simulator set it, so the
        // row failed about 1 run in 5. Nine runs on a loaded Mac (17 Nov):
        // the median read 38.9 to 44.2ms (CV 4%), the second-worst 40.8 to
        // 53.2 (8%), the worst 43.7 to 80.4 (23%). The median moves only
        // with a cost in most of the changes (30ms added to every restyle
        // read 69.4 to 74.2ms); one or two slow changes, however slow, leave
        // it where it was. So the worst keeps its own loose bound below, and
        // the first change, the one a cold path would hit (23pt, a size not
        // yet laid out), is printed as its own row, `firstFrame.first`, with no PERF line
        // in baseline.md, so `perf.sh` shows it but does not judge it.
        let sorted = totals.sorted()
        let median = (sorted[2] + sorted[3]) / 2
        let worst = sorted.last!
        print("TEXTSIZE-COST lines=\(Self.note.split(separator: "\n", omittingEmptySubsequences: false).count) "
              + "median \(String(format: "%.1f", median))ms, worst \(String(format: "%.1f", worst))ms, "
              + "first \(String(format: "%.1f", totals[0]))ms\n"
              + report.joined(separator: "\n"))
        reportPerf("TextSizeCostTests/firstFrame", seconds: median / 1000)
        reportPerf("TextSizeCostTests/firstFrame.first", seconds: totals[0] / 1000)
        // Measured 26 Oct on the simulator: 55 to 100ms (the worst), four
        // fifths of it layout, against the plan's 100ms. Loose, like
        // `typingCost`: this catches any one change, the first included,
        // that lays the whole note out twice, not noise (the worst read at
        // most 80.4ms in the nine runs); `perf.sh --compare` catches the
        // smaller regressions that are in every change.
        #expect(worst < 200, "a size change took \(Int(worst))ms to its first frame (the worst of six)")
        withExtendedLifetime(opened) {}
    }
}

#endif
