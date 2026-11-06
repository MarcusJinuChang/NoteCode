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

@Suite("Assistant in the editor", .tags(.pro))
@MainActor
struct AIEditorTests {

    nonisolated private static let note = "Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n\nAfter\n"

    private func harness(
        availability: AIAvailability = .available,
        enabled: Bool = true,
        pro: Bool = true,
        note: String = Self.note
    ) -> (EditorHarness, FakeTextModel, AssistantFeature) {
        let model = FakeTextModel()
        model.availability = availability
        model.script = { _ in .hang([]) }
        let harness = EditorHarness(note, features: [
            AssistantFeature.factory(ai: { AIAssistant(client: model, isPro: { pro }) })
        ])
        let assistant = harness.editor.feature(AssistantFeature.self)!
        AIFeatureSettings(isEnabled: enabled).apply(to: assistant.ai)
        return (harness, model, assistant)
    }

    private var inCode: Int { (Self.note as NSString).range(of: "int add").location + 2 }

    private func titles(_ menu: UIMenu) -> [String] {
        menu.children.flatMap { element -> [String] in
            if let sub = element as? UIMenu { return titles(sub) }
            return [element.title]
        }
    }

    private func menu(_ harness: EditorHarness, at offset: Int) -> UIMenu {
        harness.textView.selectedRange = NSRange(location: offset, length: 0)
        return harness.coordinator.textView(
            harness.textView,
            editMenuForTextInRanges: [NSValue(range: NSRange(location: offset, length: 0))],
            suggestedActions: []
        )!
    }

    @Test("A code block's edit menu offers Explain Block, and choosing it opens a job on that block")
    func menuItem() throws {
        let (harness, _, assistant) = harness()
        let menu = menu(harness, at: inCode)
        #expect(titles(menu).contains("Explain Block"))

        let action = try #require(menu.children.compactMap { ($0 as? UIMenu)?.children }.flatMap { $0 }.first { $0.title == "Explain Block" } as? UIAction)
        action.performWithSender(nil, target: nil)

        let job = try #require(assistant.ai.job)
        #expect(job.action == .explainBlock)
        #expect(job.languageName == "C++")
        #expect(job.chunks.count == 1)
        #expect(job.chunks[0].hasPrefix("int add(int a, int b)"))
        let end = ("Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n" as NSString).length
        #expect(job.insertionOffset == end)
        assistant.ai.dismiss()
    }

    @Test("Prose has no Explain item")
    func proseHasNone() {
        let (harness, _, _) = harness()
        #expect(!titles(menu(harness, at: 2)).contains("Explain Block"))
    }

    @Test("Switched off, or on a device that can never run it, the item is left out")
    func hidden() {
        let (off, _, _) = harness(enabled: false)
        #expect(!titles(menu(off, at: inCode)).contains("Explain Block"))

        let (ineligible, _, _) = harness(availability: .unavailable(.deviceNotEligible))
        #expect(!titles(menu(ineligible, at: inCode)).contains("Explain Block"))
    }

    @Test("While Apple Intelligence is only off, the item stays and the sheet says why")
    func shownWithReason() throws {
        let (harness, model, assistant) = harness(availability: .unavailable(.appleIntelligenceOff))
        let menu = menu(harness, at: inCode)
        #expect(titles(menu).contains("Explain Block"))

        try #require(harness.editor.actions(for: .codeBlockAtCaret, in: .codeBlockRow).first).perform()
        #expect(assistant.ai.state == .unavailable(.appleIntelligenceOff))
        #expect(model.requests.isEmpty)
        assistant.ai.dismiss()
    }

    @Test("Summarise builds a job from the note's text, its title and the caret's line")
    func summarise() throws {
        let (harness, _, assistant) = harness()
        harness.textView.selectedRange = NSRange(location: 2, length: 0)
        assistant.summariseNote(title: "Week 3")

        let job = try #require(assistant.ai.job)
        #expect(job.action == .summariseNote)
        #expect(job.title == "Week 3")
        #expect(job.chunks.joined().contains("Intro"))
        #expect(job.insertionOffset == 6)
        assistant.ai.dismiss()
    }

    @Test("Insert Below writes a quote under the block, restyled and saved, and one undo takes it back")
    func insertAndUndo() async throws {
        let (harness, _, assistant) = harness()
        let anchor = ("Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n" as NSString).length

        #expect(assistant.insertAnswer("It adds two numbers.", style: .quote, at: anchor))
        #expect(harness.stored == "Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n\n> It adds two numbers.\n\nAfter\n")
        #expect(harness.textView.text == harness.stored)

        harness.textView.undoManager?.undo()
        #expect(harness.textView.text == Self.note)
    }

    @Test("Insert Below as an output block writes a block the parser reads as output")
    func insertOutput() {
        let (harness, _, assistant) = harness()
        let anchor = ("Intro\n\n```cpp\nint add(int a, int b) { return a + b; }\n```\n" as NSString).length
        assistant.insertAnswer("Line one.", style: .output, at: anchor)

        let targets = DocumentSnapshot(text: harness.stored).targets
        #expect(targets.count == 2)
        #expect(targets[1].isOutput)
    }

    @Test("A locked note, or ink mode, takes no insertion")
    func lockedAndInk() {
        let (locked, _, lockedAssistant) = harness()
        locked.editor.setTextLocked(true)
        #expect(!lockedAssistant.canInsertAnswer)
        #expect(!lockedAssistant.insertAnswer("x", style: .quote, at: 0))
        #expect(locked.textView.text == Self.note)

        let (ink, _, inkAssistant) = harness()
        ink.editor.setMode(.ink)
        #expect(!inkAssistant.insertAnswer("x", style: .quote, at: 0))
        #expect(ink.textView.text == Self.note)
    }
    @Test("Explain Block comes after Run, Copy and Share, and is marked Pro for a free reader")
    func menuOrder() {
        let (pro, _, _) = harness()
        #expect(titles(menu(pro, at: inCode)) == ["Run Block", "Copy Block", "Share Block", "Explain Block"])

        let (free, _, _) = harness(pro: false)
        #expect(titles(menu(free, at: inCode)) == ["Run Block", "Copy Block", "Share Block", "Explain Block (Pro)"])
    }

    @Test("The options row's Explain is one word, 58 points along, labelled for VoiceOver")
    func rowAction() throws {
        let (harness, _, _) = harness()
        let actions = harness.editor.actions(for: .codeBlockAtCaret, in: .codeBlockRow)
        #expect(actions.map(\.title) == ["Explain"])
        let explain = try #require(actions.first)
        #expect(explain.label == "Explain Code Block")
        #expect(explain.rowWidth == 58)
        #expect(harness.editor.actions(for: .codeBlockAtCaret, in: .codeBlockMenu).isEmpty)
    }

    @Test("The row's Explain opens a job on the block the caret is in when it is tapped, and nothing in ink mode")
    func rowActsOnCaret() throws {
        let (harness, _, assistant) = harness()
        let explain = try #require(harness.editor.actions(for: .codeBlockAtCaret, in: .codeBlockRow).first)

        harness.editor.setMode(.ink)
        explain.perform()
        #expect(assistant.ai.job == nil)

        harness.editor.setMode(.text)
        harness.textView.selectedRange = NSRange(location: inCode, length: 0)
        explain.perform()
        #expect(assistant.ai.job?.action == .explainBlock)
        assistant.ai.dismiss()
    }

    @Test("An output block's edit menu has no Explain")
    func outputHasNone() {
        let note = "```cpp\nint x;\n```\n\n```output\nhello\n```\n"
        let (harness, _, _) = harness(note: note)
        let inOutput = (note as NSString).range(of: "hello").location + 1
        #expect(!titles(menu(harness, at: inOutput)).contains("Explain Block"))
    }

    @Test("Summarise Note is in ••• for the note, marked Pro for a free reader, and dimmed in ink mode")
    func noteMenu() throws {
        let (pro, _, _) = harness()
        let summarise = try #require(pro.editor.actions(for: .note(title: "Week 3"), in: .noteMenu).first)
        #expect(summarise.title == "Summarise Note")
        #expect(summarise.isAvailable)
        pro.editor.setMode(.ink)
        #expect(pro.editor.actions(for: .note(title: "Week 3"), in: .noteMenu).first?.isAvailable == false)

        let (free, _, _) = harness(pro: false)
        #expect(free.editor.actions(for: .note(title: "Week 3"), in: .noteMenu).map(\.title) == ["Summarise Note (Pro)"])

        let (off, _, _) = harness(enabled: false)
        #expect(off.editor.actions(for: .note(title: "Week 3"), in: .noteMenu).isEmpty)
    }
}

#endif
