//
//  RunFeatureTests.swift
//  NoteCodeTests
//
//  Run in the app as an editor feature: the gate through the editor, the
//  panel, and whether Run exists once the page has the feature. The Pro
//  state is injected: `ProStatus.shared` is bought by other suites.
//

#if canImport(UIKit)

import Observation
import Testing
import UIKit
@testable import NoteCode

@Suite("Run feature", .tags(.pro))
@MainActor
struct RunFeatureTests {

    static func editor(runner: (any CodeRunning)? = CountingRunner(), isPro: Bool) -> NoteEditor {
        let defaults = RunSessionTests.defaults()
        let editor = NoteEditor(features: [RunFeature.factory(
            runner: { runner }, isPro: { isPro }, transaction: { "jws" }, refresh: {}
        )])
        editor.run?.defaults = defaults
        return editor
    }

    @Test("Run exists as soon as the editor has the feature, and the page is told")
    func availableOnInstall() {
        // A3 (feature-audit.md): the Notes | Run switch read the runner, which
        // the page set in a `.task` after its first frame and nothing observed,
        // so the switch could stay hidden until something else redrew the bar.
        final class Told: @unchecked Sendable { var value = false }
        let editor = NoteEditor()
        let told = Told()
        let before = withObservationTracking {
            editor.run?.isAvailable == true
        } onChange: { told.value = true }
        #expect(!before)

        let runner = CountingRunner()
        editor.install([RunFeature.factory(runner: { runner }, isPro: { true }, transaction: { "" }, refresh: {})])

        #expect(told.value, "the page redraws once the feature is installed")
        #expect(editor.run?.isAvailable == true, "with the runner already set")
    }

    @Test("A free reader's Run opens the paywall and reaches nothing else")
    func freeOpensPaywall() throws {
        let runner = CountingRunner()
        let harness = RunHarness("```cpp\nint x;\n```\n", editor: Self.editor(runner: runner, isPro: false))
        let feature = try #require(harness.editor.feature(RunFeature.self))
        var paywalls = 0
        feature.onNeedsPro = { paywalls += 1 }

        harness.coordinator.run(try harness.firstBlock(), from: harness.textView)

        #expect(paywalls == 1)
        #expect(runner.runs == 0)
        #expect(harness.opened.isEmpty, "no site either")
        #expect(feature.session.isOpen == false)
    }

    @Test("Pro's Run opens the panel on that block and runs it")
    func proRunsInPanel() async throws {
        let runner = CountingRunner()
        let harness = RunHarness("```python\nprint(1)\n```\n\n```cpp\nint x;\n```\n", editor: Self.editor(runner: runner, isPro: true))
        let feature = try #require(harness.editor.feature(RunFeature.self))
        let source = (harness.textView.text ?? "").nativeUTF8
        let second = try #require(DocumentSnapshot(text: source).targets.last)

        harness.coordinator.run(second, from: harness.textView)
        await feature.session.task?.value

        #expect(feature.session.isOpen)
        #expect(feature.session.chosen?.ordinal == second.id.ordinal)
        #expect(runner.runs == 1)
        #expect(harness.opened.isEmpty)
    }

    @Test("With no service the feature lets Run go to the site")
    func noServiceFallsThrough() throws {
        let harness = RunHarness("```cpp\nint x;\n```\n", editor: Self.editor(runner: nil, isPro: true))
        let block = try harness.firstBlock()

        harness.coordinator.run(block, from: harness.textView)

        #expect(harness.opened == [CodeDestination.request(for: block.code, language: .cpp).url])
    }

    @Test("The panel has the note's blocks when the feature arrives after the text view")
    func blocksOnLateInstall() throws {
        let harness = RunHarness("```cpp\nint x;\n```\n")
        #expect(harness.editor.run == nil)
        harness.editor.install([RunFeature.factory(runner: { CountingRunner() }, isPro: { true }, transaction: { "" }, refresh: {})])
        #expect(harness.editor.run?.blocks.count == 1)
    }
}

#endif
