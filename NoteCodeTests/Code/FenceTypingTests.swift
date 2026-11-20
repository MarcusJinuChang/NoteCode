//
//  FenceTypingTests.swift
//  NoteCodeTests
//
//  Typing a fence line inside a code block, a key at a time, leaves the
//  note's blocks where they are until the line is finished.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Typing a fence inside a block", .tags(.editor))
@MainActor
struct FenceTypingTests {

    static let note = "Prose above.\n```cpp\nint a = 1;\n\nint b = 2; // below\n```\nProse below."

    /// The code blocks the bars, the styling and Run see.
    static func blocks(_ harness: EditorHarness) -> [String] {
        harness.coordinator.snapshot(of: harness.textView).targets.map(\.code)
    }

    /// The empty line inside the block.
    static func emptyLine(_ harness: EditorHarness) -> Int {
        harness.offset(of: "int a = 1;\n") + ("int a = 1;\n" as NSString).length
    }

    /// The device pass's code-3: the third backtick of ```swift made the
    /// line a bare fence for one keystroke, which closed the block there, so
    /// the code below turned to prose and the old closing fence opened a
    /// block that took the prose below.
    @Test("```swift typed a key at a time keeps one block throughout")
    func taggedFenceKeepsTheBlock() async throws {
        let harness = EditorHarness(Self.note)
        var caret = Self.emptyLine(harness)
        for key in "```swift" {
            harness.type(String(key), at: caret)
            caret += 1
            let blocks = Self.blocks(harness)
            #expect(blocks.count == 1, "after \(key): \(blocks)")
            #expect(blocks.first?.contains("int b = 2; // below") == true, "after \(key): \(blocks)")
            #expect(blocks.first?.contains("Prose below.") == false, "after \(key): \(blocks)")
        }
    }

    /// Backspacing ```s back to ``` is the same half-typed line.
    @Test("Backspacing a tag back to a bare fence keeps one block")
    func backspaceToBareFence() async throws {
        let harness = EditorHarness(Self.note.replacingOccurrences(of: "int a = 1;\n\n", with: "int a = 1;\n```s\n"))
        let end = harness.offset(of: "```s") + 4
        harness.textView.selectedRange = NSRange(location: end, length: 0)
        harness.textView.deleteBackward()
        harness.coordinator.textViewDidChange(harness.textView)
        #expect(Self.blocks(harness).count == 1)
    }

    /// A bare fence that is meant to close the block does, once the line is
    /// left: by Return, or by the caret moving away.
    @Test("A typed bare fence closes the block on Return", arguments: [true, false])
    func bareFenceClosesOnLeaving(byReturn: Bool) async throws {
        let harness = EditorHarness(Self.note)
        var caret = Self.emptyLine(harness)
        for key in "```" {
            harness.type(String(key), at: caret)
            caret += 1
        }
        if byReturn {
            harness.type("\n", at: caret)
        } else {
            try await harness.caret(at: harness.offset(of: "Prose above."))
        }
        let blocks = Self.blocks(harness)
        #expect(blocks.count == 2, "\(blocks)")
        #expect(blocks.first == "int a = 1;\n", "\(blocks)")
    }

    /// Typing the closing fence of a block at the end of the note still
    /// closes it once the line is left.
    @Test("Typing a closing fence at the end of the note")
    func closingFenceAtEnd() async throws {
        let harness = EditorHarness("```cpp\nint a;\n")
        var caret = harness.source.length
        for key in "```" {
            harness.type(String(key), at: caret)
            caret += 1
        }
        harness.type("\nAfter.", at: caret)
        let snapshot = harness.coordinator.snapshot(of: harness.textView)
        #expect(snapshot.codeRanges.map(\.isClosed) == [true])
    }
}

#endif
