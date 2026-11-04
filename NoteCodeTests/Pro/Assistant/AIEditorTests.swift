//
//  AIEditorTests.swift
//  NoteCodeTests
//
//  The assistant inside a real text view: the edit menu's item, the jobs the
//  editor builds, and Insert Below as an undoable edit.
//

#if canImport(UIKit)

import UIKit
import Testing
@testable import NoteCode

@Suite("Assistant in the editor")
@MainActor
struct AIEditorTests {

    typealias Harness = CodeFenceDisplayTests.Harness

    private static let note = "Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n\nAfter\n"

    private func harness(
        availability: AIAvailability = .available,
        enabled: Bool = true
    ) -> (Harness, FakeTextModel) {
        let harness = Harness(Self.note)
        let model = FakeTextModel()
        model.availability = availability
        model.script = { _ in .hang([]) }
        harness.editor.ai = AIAssistant(client: model)
        AIFeatureSettings(isEnabled: enabled).apply(to: harness.editor.ai)
        return (harness, model)
    }

    private var inCode: Int { (Self.note as NSString).range(of: "int add").location + 2 }

    private func titles(_ menu: UIMenu) -> [String] {
        menu.children.flatMap { element -> [String] in
            if let sub = element as? UIMenu { return titles(sub) }
            return [element.title]
        }
    }

    private func menu(_ harness: Harness, at offset: Int) -> UIMenu {
        harness.textView.selectedRange = NSRange(location: offset, length: 0)
        return harness.coordinator.textView(
            harness.textView,
            editMenuForTextInRanges: [NSValue(range: NSRange(location: offset, length: 0))],
            suggestedActions: []
        )!
    }

    @Test("A code block's edit menu offers Explain Block, and choosing it opens a job on that block")
    func menuItem() throws {
        let (harness, _) = harness()
        let menu = menu(harness, at: inCode)
        #expect(titles(menu).contains("Explain Block"))

        let action = try #require(menu.children.compactMap { ($0 as? UIMenu)?.children }.flatMap { $0 }.first { $0.title == "Explain Block" } as? UIAction)
        action.performWithSender(nil, target: nil)

        let job = try #require(harness.editor.ai.job)
        #expect(job.action == .explainBlock)
        #expect(job.languageName == "C++")
        #expect(job.chunks.count == 1)
        #expect(job.chunks[0].hasPrefix("int add(int a, int b)"))
        let end = ("Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n" as NSString).length
        #expect(job.insertionOffset == end)
        harness.editor.ai.dismiss()
    }

    @Test("Prose has no Explain item")
    func proseHasNone() {
        let (harness, _) = harness()
        #expect(!titles(menu(harness, at: 2)).contains("Explain Block"))
    }

    @Test("Switched off, or on a device that can never run it, the item is left out")
    func hidden() {
        let (off, _) = harness(enabled: false)
        #expect(!titles(menu(off, at: inCode)).contains("Explain Block"))

        let (ineligible, _) = harness(availability: .unavailable(.deviceNotEligible))
        #expect(!titles(menu(ineligible, at: inCode)).contains("Explain Block"))
    }

    @Test("While Apple Intelligence is only off, the item stays and the sheet says why")
    func shownWithReason() throws {
        let (harness, model) = harness(availability: .unavailable(.appleIntelligenceOff))
        let menu = menu(harness, at: inCode)
        #expect(titles(menu).contains("Explain Block"))

        harness.editor.explainBlockAtCaret?()
        #expect(harness.editor.ai.state == .unavailable(.appleIntelligenceOff))
        #expect(model.requests.isEmpty)
        harness.editor.ai.dismiss()
    }

    @Test("Summarise builds a job from the note's text, its title and the caret's line")
    func summarise() throws {
        let (harness, _) = harness()
        harness.textView.selectedRange = NSRange(location: 2, length: 0)
        harness.editor.summariseNote(title: "Week 3")

        let job = try #require(harness.editor.ai.job)
        #expect(job.action == .summariseNote)
        #expect(job.title == "Week 3")
        #expect(job.chunks.joined().contains("Intro"))
        #expect(job.insertionOffset == 6)
        harness.editor.ai.dismiss()
    }

    @Test("Insert Below writes a quote under the block, restyled and saved, and one undo takes it back")
    func insertAndUndo() async throws {
        let (harness, _) = harness()
        let anchor = ("Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n" as NSString).length

        #expect(harness.editor.insertAnswer("It adds two numbers.", style: .quote, at: anchor))
        #expect(harness.stored == "Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n\n> It adds two numbers.\n\nAfter\n")
        #expect(harness.textView.text == harness.stored)

        harness.textView.undoManager?.undo()
        #expect(harness.textView.text == Self.note)
    }

    @Test("Insert Below as an output block writes a block the parser reads as output")
    func insertOutput() {
        let (harness, _) = harness()
        let anchor = ("Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n" as NSString).length
        harness.editor.insertAnswer("Line one.", style: .output, at: anchor)

        let targets = CodeBlockAction.targets(in: harness.stored, blocks: DocumentParser.parse(harness.stored))
        #expect(targets.count == 2)
        #expect(targets[1].isOutput)
    }

    @Test("A locked note, or ink mode, takes no insertion")
    func lockedAndInk() {
        let (locked, _) = harness()
        locked.editor.setTextLocked(true)
        #expect(!locked.editor.canInsertAnswer)
        #expect(!locked.editor.insertAnswer("x", style: .quote, at: 0))
        #expect(locked.textView.text == Self.note)

        let (ink, _) = harness()
        ink.editor.setMode(.ink)
        #expect(!ink.editor.insertAnswer("x", style: .quote, at: 0))
        #expect(ink.textView.text == Self.note)
    }
}

#endif
