//
//  MarkerDimmingTests.swift
//  NoteCodeTests
//
//  Settings › Writing › Markers (feedback item 9): off, dim or full for
//  heading marks, list bullets, checkboxes and fence lines.
//

#if canImport(UIKit)

import Testing
import UIKit

@testable import NoteCode

@Suite("Marker dimming")
@MainActor
struct MarkerDimmingTests {

    static let note = "# Heading\n- bullet item\n1. numbered item\n- [ ] a box\n```cpp\nint a;\n```\n```output\n42\n```\n"

    @Test("The keys are stable, and the default is today's look")
    func keysAndDefault() {
        #expect(MarkerDimming.headingsKey == "markerDimming.headings")
        #expect(MarkerDimming.bulletsKey == "markerDimming.bullets")
        #expect(MarkerDimming.checkboxesKey == "markerDimming.checkboxes")
        #expect(MarkerDimming.fencesKey == "markerDimming.fences")
        #expect(MarkerLevel.allCases.map(\.rawValue) == ["off", "dim", "full"])

        let standard = MarkerDimming.standard
        #expect([standard.headings, standard.bullets, standard.checkboxes, standard.fences].allSatisfy { $0 == .dim })
        // The colours markers had before there were settings.
        #expect(standard.headingTextColour == DocumentStyler.markerColor)
        #expect(standard.headingColour == .secondaryLabel, "the hashes in the margin")
        #expect(standard.bulletColour == DocumentStyler.markerColor)
        #expect(standard.checkboxColour == .tertiaryLabel)
        #expect(standard.fenceColour(isOutput: false) == DocumentStyler.markerColor)
        #expect(standard.fenceColour(isOutput: true) == CodeOutputPanel.labelColor)
    }

    @Test("Off hides without moving, dim is the grey, full is the text's colour")
    func colours() {
        let off = MarkerDimming(headings: .off, bullets: .off, checkboxes: .off, fences: .off)
        #expect(off.headingColour == nil && off.checkboxColour == nil)
        #expect(off.bulletColour == .clear && off.headingTextColour == .clear)
        #expect(off.fenceColour(isOutput: false) == .clear && off.fenceColour(isOutput: true) == .clear)

        let full = MarkerDimming(headings: .full, bullets: .full, checkboxes: .full, fences: .full)
        #expect(full.headingColour == .label && full.bulletColour == .label && full.checkboxColour == .label)
        #expect(full.fenceColour(isOutput: false) == .label)
        #expect(full.fenceColour(isOutput: true) == CodeOutputPanel.textColor)
    }

    // MARK: Styled

    /// The colour at the first character of `text`'s first occurrence.
    private func colour(_ harness: CodeFenceDisplayTests.Harness, of text: String, backwards: Bool = false) -> UIColor? {
        harness.textView.textStorage.attribute(
            .foregroundColor, at: harness.offset(of: text, backwards: backwards), effectiveRange: nil
        ) as? UIColor
    }

    private func harness(_ dimming: MarkerDimming) -> CodeFenceDisplayTests.Harness {
        let harness = CodeFenceDisplayTests.Harness(Self.note)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.coordinator.setMarkerDimming(dimming, in: harness.textView)
        harness.layOut()
        return harness
    }

    @Test("Each kind of marker is coloured by its own setting", arguments: MarkerLevel.allCases)
    func stylerFollowsEachSetting(level: MarkerLevel) {
        // One kind at a time, the others left dim: a setting reaches only its marker.
        for kind in [\MarkerDimming.headings, \.bullets, \.checkboxes, \.fences] {
            var dimming = MarkerDimming.standard
            dimming[keyPath: kind] = level
            let h = harness(dimming)
            #expect(colour(h, of: "# Heading") == dimming.headingTextColour)
            #expect(colour(h, of: "- bullet") == dimming.bulletColour)
            #expect(colour(h, of: "1. numbered") == dimming.bulletColour, "numbers are list markers too")
            #expect(colour(h, of: "```cpp") == dimming.fenceColour(isOutput: false))
            #expect(colour(h, of: "```output") == dimming.fenceColour(isOutput: true))
            // The closing fence is a fence line too.
            #expect(colour(h, of: "```\n```output") == dimming.fenceColour(isOutput: false))
        }
    }

    @Test("A change restyles the note and moves no line")
    func changeRestylesAndMovesNothing() async throws {
        let h = harness(.standard)
        try await h.settle()
        let before = CodeBlockRoomTests.lines(of: h.textView).map(\.frame)
        #expect(colour(h, of: "- bullet") == DocumentStyler.markerColor)

        h.coordinator.setMarkerDimming(MarkerDimming(headings: .off, bullets: .full, checkboxes: .off, fences: .off), in: h.textView)
        h.layOut()
        try await h.settle()
        #expect(colour(h, of: "- bullet") == .label)
        #expect(colour(h, of: "```cpp") == .clear)
        #expect(CodeBlockRoomTests.lines(of: h.textView).map(\.frame) == before, "marker colours are paint, not layout")

        h.coordinator.setMarkerDimming(.standard, in: h.textView)
        h.layOut()
        #expect(colour(h, of: "- bullet") == DocumentStyler.markerColor)
        #expect(colour(h, of: "```cpp") == DocumentStyler.markerColor)
    }

    @Test("Typing after a hidden fence line doesn't pick up its colour")
    func typingDoesNotInheritAHiddenFence() throws {
        let h = harness(MarkerDimming(fences: .off))
        let end = h.offset(of: "```cpp") + "```cpp".count
        h.textView.selectedRange = NSRange(location: end, length: 0)
        h.coordinator.textViewDidChangeSelection(h.textView)
        let typed = h.textView.typingAttributes[.foregroundColor] as? UIColor
        #expect(typed != .clear, "text typed after the tag would be invisible")
    }

    // MARK: Drawn

    private func margin(of harness: CodeFenceDisplayTests.Harness, line text: String) -> CGRect {
        let rect = harness.rect(of: text)
        return CGRect(x: 8, y: rect.minY, width: rect.minX - 8 - 3, height: rect.height)
    }

    @Test("A heading's hashes in the margin: none when off, grey when dim, darker when full")
    func hashesInTheMargin() async throws {
        var darkness: [MarkerLevel: Double] = [:]
        var pixels: [MarkerLevel: Int] = [:]
        for level in MarkerLevel.allCases {
            let h = CodeFenceDisplayTests.Harness(Self.note, showMarkdown: .always)
            h.coordinator.setRendersMarkdown(true, in: h.textView)
            h.coordinator.setMarkerDimming(MarkerDimming(headings: level), in: h.textView)
            h.layOut()
            try await h.caret(at: h.offset(of: "bullet"))
            let region = margin(of: h, line: "Heading")
            pixels[level] = CodeFenceDisplayTests.inkPixels(of: h.textView, in: region)
            let mean = CodeFenceDisplayTests.meanColor(of: h.textView, in: region)
            darkness[level] = 255 - (mean.r + mean.g + mean.b) / 3
        }
        #expect(pixels[.off] == 0, "hashes drawn with the setting off: \(pixels)")
        #expect((pixels[.dim] ?? 0) > 20 && (pixels[.full] ?? 0) > 20, "\(pixels)")
        #expect((darkness[.full] ?? 0) > (darkness[.dim] ?? 0), "full is darker than dim on a light page: \(darkness)")
    }

    @Test("A checkbox's outline: none when off, drawn when dim or full; a ticked box stays")
    func checkboxOutline() async throws {
        func box(_ level: MarkerLevel, note: String) async throws -> (pixels: Int, mean: Double) {
            let h = CodeFenceDisplayTests.Harness(note)
            h.coordinator.setRendersMarkdown(true, in: h.textView)
            h.coordinator.setMarkerDimming(MarkerDimming(checkboxes: level), in: h.textView)
            h.layOut()
            let manager = try #require(h.textView.textLayoutManager)
            manager.ensureLayout(for: manager.documentRange)
            var rect: CGRect?
            manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragment in
                guard let list = fragment as? ChecklistLayoutFragment, let place = list.boxRect() else { return true }
                rect = place.box.offsetBy(
                    dx: fragment.layoutFragmentFrame.minX + h.textView.textContainerInset.left,
                    dy: fragment.layoutFragmentFrame.minY + h.textView.textContainerInset.top
                )
                return false
            }
            let area = try #require(rect).insetBy(dx: -1, dy: -1)
            let mean = CodeFenceDisplayTests.meanColor(of: h.textView, in: area)
            return (CodeFenceDisplayTests.inkPixels(of: h.textView, in: area), 255 - (mean.r + mean.g + mean.b) / 3)
        }
        let off = try await box(.off, note: "- [ ] a box\n")
        let dim = try await box(.dim, note: "- [ ] a box\n")
        let full = try await box(.full, note: "- [ ] a box\n")
        #expect(off.pixels == 0, "an outline drawn with the setting off: \(off)")
        #expect(dim.pixels > 20 && full.pixels > 20)
        #expect(full.mean > dim.mean, "full is darker than dim: \(full.mean) \(dim.mean)")

        let ticked = try await box(.off, note: "- [x] done\n")
        #expect(ticked.pixels > 20, "a ticked box is state, not a marker to turn off")
    }
}

#endif
