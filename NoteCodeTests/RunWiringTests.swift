//
//  RunWiringTests.swift
//  NoteCodeTests
//
//  R4: the gate, the in-app destination, Keep in Note and the error links.
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

/// Counts what reaches the service.
final class CountingRunner: CodeRunning, @unchecked Sendable {
    private(set) var runs = 0
    var error: RunServiceError?
    func run(_ job: RunJob) async throws -> RunResult {
        runs += 1
        if let error { throw error }
        return RunResult(status: .ok, stdout: "out\n")
    }
}

@Suite("Run wiring")
@MainActor
struct RunWiringTests {

    // MARK: The gate and the destination

    @Test("A free reader's Run opens the paywall whatever the page points at")
    func freeGate() {
        for destination in [CodeDestination.inApp, .programiz, .compilerExplorer] {
            #expect(RunRoute.route(hasRunner: true, isPro: false, destination: destination) == .paywall)
        }
    }

    @Test("Pro runs in the app when the page points there, otherwise redirects")
    func proRoute() {
        #expect(RunRoute.route(hasRunner: true, isPro: true, destination: .inApp) == .inApp)
        #expect(RunRoute.route(hasRunner: true, isPro: true, destination: .onlineGDB) == .redirect)
    }

    @Test("With no service nothing in-app is visible, and nothing is gated")
    func noService() {
        #expect(RunRoute.route(hasRunner: false, isPro: false, destination: .inApp) == .redirect)
        #expect(RunServiceFactory.make(service: nil) == nil || DebugLaunchOptions.current.runStub != nil)
        #expect(!CodeDestination.choices(inAppAvailable: false).contains(.inApp))
        #expect(RunDestinationPreference.resolve([nil, "notecode"], inAppAvailable: false) == .default)
        #expect(RunDestinationPreference.resolve([], inAppAvailable: false) == .default)
    }

    @Test("A free reader's tap reaches no service")
    func freeMakesNoRequest() {
        let runner = CountingRunner()
        let session = RunSession()
        session.runner = runner
        if RunRoute.route(hasRunner: session.isAvailable, isPro: false, destination: .inApp) == .inApp {
            session.run(transaction: "")
        }
        #expect(runner.runs == 0)
    }

    @Test("A 402 tells the editor the subscription isn't held")
    func refused() async {
        let runner = CountingRunner()
        runner.error = .notSubscribed
        let session = RunSession()
        session.defaults = RunSessionTests.defaults()
        session.runner = runner
        session.update(blocks: [Self.target(0, "print(1)")])
        var told = 0
        session.onNotSubscribed = { told += 1 }
        session.run(transaction: "jws")
        await session.task?.value
        #expect(told == 1)
    }

    @Test("The destination resolves to in-app and back")
    func resolution() {
        #expect(RunDestinationPreference.resolve([], inAppAvailable: true) == .inApp)
        #expect(RunDestinationPreference.resolve([nil, nil, "notecode"], inAppAvailable: true) == .inApp)
        #expect(RunDestinationPreference.resolve(["programiz", nil, "notecode"], inAppAvailable: true) == .programiz)
        #expect(RunDestinationPreference.resolve(["notecode", "godbolt"], inAppAvailable: true) == .inApp)
        #expect(CodeDestination(id: CodeDestination.inApp.id) == .inApp)
        // The site it falls back to skips the app.
        #expect(RunDestinationPreference.resolveSite(["notecode", "onlinegdb"]) == .onlineGDB)
        #expect(RunDestinationPreference.resolveSite(["notecode"]) == .default)
        // A redirect asked of "In NoteCode" lands on a site.
        let request = CodeDestination.request(for: "x", language: .cpp, preferring: .inApp)
        #expect(request.destination == .default)
    }

    // MARK: Keep in Note

    private static func target(_ ordinal: Int, _ code: String) -> CodeBlockTarget {
        CodeBlockTarget(
            id: CodeBlockID(ordinal: ordinal, code: code),
            range: NSRange(location: 0, length: code.utf16.count),
            language: .python, code: code, tag: "python"
        )
    }

    private func targets(_ source: String) -> [CodeBlockTarget] {
        CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source))
    }

    @Test("Keep in Note inserts under the code, then replaces on a second run")
    func keepOnce() throws {
        var source = "Intro\n```python\nprint(1)\n```\nAfter\n"
        let first = try #require(KeepInNote.edit(output: "1", forBlockAt: 0, in: source, targets: targets(source)))
        source = first.applied(to: source)
        #expect(source == "Intro\n```python\nprint(1)\n```\n```output\n1\n```\nAfter\n")

        let second = try #require(KeepInNote.edit(output: "2\n3", forBlockAt: 0, in: source, targets: targets(source)))
        source = second.applied(to: source)
        #expect(source == "Intro\n```python\nprint(1)\n```\n```output\n2\n3\n```\nAfter\n")
        #expect(source.components(separatedBy: "```output").count == 2, "never duplicated")
    }

    @Test("Keep in Note on the note's last line adds the missing newline")
    func keepAtEnd() throws {
        let source = "```python\nprint(1)\n```"
        let edit = try #require(KeepInNote.edit(output: "1", forBlockAt: 0, in: source, targets: targets(source)))
        #expect(edit.applied(to: source) == "```python\nprint(1)\n```\n```output\n1\n```\n")
    }

    @Test("Output holding a fence gets a longer one")
    func fenced() {
        #expect(KeepInNote.fenced("a ``` b").hasPrefix("````output\n"))
        #expect(KeepInNote.fenced("plain") == "```output\nplain\n```")
    }

    @Test("What is kept: stdout, compile output, stderr; nothing when empty")
    func keptText() {
        #expect(KeepInNote.text(of: RunResult(status: .ok, stdout: "a\n", stderr: "b\n")) == "a\nb")
        #expect(KeepInNote.text(of: RunResult(status: .ok)) == nil)
    }

    @Test("Keep in Note is one undo step in the text view")
    func keepUndo() async throws {
        let original = "Intro\n```python\nprint(1)\n```\nAfter\n"
        var stored = original
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 1200))
        let textView = DocumentTextView.makeConfiguredTextView()
        let editor = NoteEditor()
        let page = PageView(textView: textView)
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { stored }, set: { stored = $0 }))
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        coordinator.observeEdits(of: textView)
        coordinator.attachOverlay(to: textView)
        textView.text = original
        coordinator.invalidateStyling()
        coordinator.restyle(textView)
        page.frame = CGRect(x: 0, y: 0, width: 872, height: 1100)
        window.addSubview(page)
        window.makeKeyAndVisible()
        editor.attach(textView, canvas: page.canvas, page: page)
        coordinator.connect(editor, to: textView)

        // Runs are seconds apart, so a turn of the run loop apart (undo groups
        // what happens in one).
        editor.run.keepInNote?(0, "1")
        try await Task.sleep(for: .milliseconds(100))
        editor.run.keepInNote?(0, "2")
        try await Task.sleep(for: .milliseconds(200))
        #expect(textView.text == "Intro\n```python\nprint(1)\n```\n```output\n2\n```\nAfter\n")

        textView.undoManager?.undo()
        #expect(textView.text == "Intro\n```python\nprint(1)\n```\n```output\n1\n```\nAfter\n", "the second run was one step")
        textView.undoManager?.undo()
        #expect(textView.text == original, "and the first")
    }

    // MARK: Links

    @Test("A compile error's line lands the caret on that line of the block")
    func linkLine() throws {
        let source = "Intro\n```cpp\nint a;\nint b;\nint c;\n```\n"
        let target = try #require(targets(source).first)
        let offset = try #require(KeepInNote.caretOffset(line: 3, in: target, source: source))
        #expect((source as NSString).substring(from: offset).hasPrefix("int c;"))
        #expect(KeepInNote.caretOffset(line: 1, in: target, source: source) == (source as NSString).range(of: "int a;").location)
        #expect(KeepInNote.caretOffset(line: 9, in: target, source: source) == nil)
    }

    @Test("The coordinator puts the caret on the linked line")
    func linkCaret() async throws {
        let source = "Intro\n```cpp\nint a;\nint b;\n```\n"
        var stored = source
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 1200))
        let textView = DocumentTextView.makeConfiguredTextView()
        let editor = NoteEditor()
        let page = PageView(textView: textView)
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { stored }, set: { stored = $0 }))
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        coordinator.observeEdits(of: textView)
        textView.text = source
        coordinator.invalidateStyling()
        coordinator.restyle(textView)
        page.frame = CGRect(x: 0, y: 0, width: 872, height: 1100)
        window.addSubview(page)
        window.makeKeyAndVisible()
        editor.attach(textView, canvas: page.canvas, page: page)
        coordinator.connect(editor, to: textView)

        let block = try #require(editor.run.blocks.first)
        editor.run.showLine?(block, 2)
        #expect(textView.selectedRange.location == (source as NSString).range(of: "int b;").location)
    }
}

#endif
