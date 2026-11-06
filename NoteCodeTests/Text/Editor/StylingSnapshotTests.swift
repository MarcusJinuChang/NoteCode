//
//  StylingSnapshotTests.swift
//  NoteCodeTests
//
//  2T8: `DocumentStyler.applyStyling` is split into one function per block
//  kind. This pins what it produces today: every attribute run over a note
//  that has every block kind, written out as text and compared with a file
//  taken before the split. Set NOTECODE_RECORD to rewrite the file (with
//  TEST_RUNNER_ in front, so xcodebuild hands it to the test process).
//

#if canImport(UIKit)

import Foundation
import Testing
import UIKit
@testable import NoteCode

@Suite("Styling snapshot", .tags(.editor))
@MainActor
struct StylingSnapshotTests {

    /// One of every block kind, with inline marks, a ticked and an unticked
    /// checkbox, nesting, an output block and an unclosed fence.
    nonisolated static let everyBlock = """
    # Heading one
    ## Heading **two** with `code`
    Prose with *emphasis*, **bold**, ~~gone~~, ==marked== and a [link](https://example.com) and $x^2$.
    - bullet item with **bold**
      - nested bullet
    1. ordered item
    - [ ] open task
    - [x] done task with *style*
    > quoted text with `code`
    >> deeper quote
    ---
    $$
    \\frac{a}{b} = c
    $$
    ```cpp
    int main() {
        return 0;
    }
    ```
    ```output
    0
    ```
    ```python
    print("unclosed")
    """

    private func dump(_ source: String, rendered: Bool) -> String {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 800, height: 1000)
        textView.text = source
        DocumentStyler.applyStyling(to: textView, rendered: rendered)
        let storage = textView.textStorage
        let text = storage.string as NSString
        var out = "rendered=\(rendered)\n"
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            let words = text.substring(with: range).replacingOccurrences(of: "\n", with: "\\n")
            out += "[\(range.location),\(range.length)] \(words.prefix(24))\n"
            for key in attributes.keys.map(\.rawValue).sorted() {
                let value = attributes[NSAttributedString.Key(key)]!
                let described = Self.describe(value)
                out += "    \(key) = \(described)\n"
            }
        }
        return out
    }

    /// Colours resolved in both appearances, and addresses taken out, so the
    /// text is the same from run to run.
    private static func describe(_ value: Any) -> String {
        if let colour = value as? UIColor {
            func rgba(_ style: UIUserInterfaceStyle) -> String {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                colour.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
                return String(format: "%.3f,%.3f,%.3f,%.3f", r, g, b, a)
            }
            return "colour light(\(rgba(.light))) dark(\(rgba(.dark)))"
        }
        return "\(value)"
            .replacingOccurrences(of: "\n", with: " | ")
            .replacing(/0x[0-9a-f]+/, with: "0x")
    }

    private var golden: URL {
        TestPaths.repoRoot.appendingPathComponent("NoteCodeTests/Text/Editor/Snapshots/styling.txt")
    }

    @Test("Styling every block kind matches the snapshot taken before the split")
    func matchesSnapshot() throws {
        var out = ""
        for source in [Self.everyBlock, TestFixtures.codeFenceNote, TestFixtures.severalPages] {
            for rendered in [false, true] {
                out += dump(source, rendered: rendered) + "====\n"
            }
        }
        if ProcessInfo.processInfo.environment["NOTECODE_RECORD"] != nil {
            try FileManager.default.createDirectory(at: golden.deletingLastPathComponent(), withIntermediateDirectories: true)
            try out.write(to: golden, atomically: true, encoding: .utf8)
            return
        }
        let expected = try String(contentsOf: golden, encoding: .utf8)
        #expect(out == expected)
    }
}

#endif
