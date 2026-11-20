//
//  TestFixtures.swift
//  NoteCodeTests
//
//  Notes the tests share, so a test names the note it needs instead of
//  building it again: the seed notes `-debug-note` opens, a note of several
//  pages, and ink in bulk.
//

#if canImport(UIKit)

import PaperKit
import UIKit
@testable import NoteCode

enum TestFixtures {

    /// A note with prose, a cpp block and prose after it.
    nonisolated static let codeFenceNote = "Prose before\n```cpp\nint value = query(gap);\nint other = 2;\n```\nProse after the block\nand more text\n"

    /// Lines that wrap on a portrait page and fit on a landscape one.
    nonisolated static let longProse = (0..<40)
        .map { "Line \($0): an invariant holds before and after every iteration of the loop, which is what the proof rests on." }
        .joined(separator: "\n")

    /// Several pages of prose, wrapped paragraphs, headings and code, with
    /// descenders — so page breaks land mid-paragraph as well as between lines.
    nonisolated static let severalPages = (0..<220)
        .map { index -> String in
            switch index % 30 {
            case 0:  return "## Section \(index) gjpqy"
            case 11: return "```cpp\nint query(gap g) { return g.jump(); }\n```"
            default:
                return index % 3 == 0
                    ? "Line \(index): " + String(repeating: "the loop invariant holds before and after every iteration, ", count: 3)
                    : "Line \(index): the loop invariant holds before and after every iteration."
            }
        }
        .joined(separator: "\n")

    #if DEBUG
    /// The notes `-debug-note pages|code|empty` open.
    static func seedNote(_ fixture: DebugFixture) -> String { fixture.text }
    #endif

    /// A markup with `count` strokes a line apart, as the cost tests draw them.
    static func inkHeavy(strokes count: Int) -> PaperMarkup {
        TestInk.markup(strokesAt: (0..<count).map { CGFloat(100 + $0 * 40) })
    }
}

#endif
