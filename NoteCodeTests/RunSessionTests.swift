//
//  RunSessionTests.swift
//  NoteCodeTests
//
//  The Run panel's state: staleness, a block surviving edits above it, input
//  kept per block. No UI.
//

import Testing
import Foundation
@testable import NoteCode

struct StubRunner: CodeRunning {
    var result: RunResult = RunResult(status: .ok, stdout: "hi\n", runsLeft: 7)
    var error: RunServiceError?
    func run(_ job: RunJob) async throws -> RunResult {
        if let error { throw error }
        return result
    }
}

@MainActor
@Suite struct RunSessionTests {
    private func target(_ ordinal: Int, _ code: String, at location: Int = 0) -> CodeBlockTarget {
        CodeBlockTarget(
            id: CodeBlockID(ordinal: ordinal, code: code),
            range: NSRange(location: location, length: code.utf16.count),
            language: .python, code: code, tag: "python"
        )
    }

    /// Defaults of the test's own, where the reader has or hasn't agreed to
    /// `RunDisclosure`; with it agreed, a run goes straight out.
    static func defaults(disclosed: Bool = true) -> UserDefaults {
        let name = "RunSessionTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        if disclosed { RunDisclosure.markAccepted(in: d) }
        return d
    }

    private func session(_ codes: [String], runner: any CodeRunning = StubRunner(), disclosed: Bool = true) -> RunSession {
        let s = RunSession()
        s.defaults = Self.defaults(disclosed: disclosed)
        s.runner = runner
        s.update(blocks: codes.enumerated().map { target($0.offset, $0.element) })
        return s
    }

    @Test func resultGoesStaleWhenTheCodeChanges() async {
        let s = session(["print(1)"])
        s.run(transaction: "jws")
        await s.task?.value
        let block = s.blocks[0]
        #expect(s.record(for: block) != nil)
        #expect(!s.isStale(block))

        s.update(blocks: [target(0, "print(2)")])
        #expect(s.isStale(s.blocks[0]))
        #expect(s.record(for: s.blocks[0]) != nil)
    }

    @Test func chosenBlockSurvivesABlockInsertedAbove() {
        let s = session(["a = 1", "b = 2"])
        s.choose(s.blocks[1])
        s.update(blocks: [target(0, "new = 0"), target(1, "a = 1"), target(2, "b = 2")])
        #expect(s.chosen?.code == "b = 2")
    }

    @Test func chosenBlockSurvivesABlockRemovedAbove() {
        let s = session(["a = 1", "b = 2"])
        s.choose(s.blocks[1])
        s.update(blocks: [target(0, "b = 2")])
        #expect(s.chosen?.code == "b = 2")
    }

    @Test func chosenBlockSurvivesItsOwnEdit() {
        let s = session(["a = 1", "b = 2"])
        s.choose(s.blocks[1])
        s.update(blocks: [target(0, "a = 1"), target(1, "b = 3")])
        #expect(s.chosen?.code == "b = 3")
    }

    @Test func inputIsKeptPerBlockAndFollowsItsBlock() {
        let s = session(["a = 1", "b = 2"])
        s.setInput("one", for: s.blocks[0])
        s.setInput("two", for: s.blocks[1])
        s.update(blocks: [target(0, "new"), target(1, "a = 1"), target(2, "b = 2")])
        #expect(s.input(for: s.blocks[0]) == "")
        #expect(s.input(for: s.blocks[1]) == "one")
        #expect(s.input(for: s.blocks[2]) == "two")
    }

    @Test func resultStaysWithItsBlockWhenOneIsInsertedAbove() async {
        let s = session(["a = 1"])
        s.run(transaction: "")
        await s.task?.value
        s.update(blocks: [target(0, "new"), target(1, "a = 1")])
        #expect(s.record(for: s.blocks[0]) == nil)
        #expect(s.record(for: s.blocks[1]) != nil)
        #expect(!s.isStale(s.blocks[1]))
    }

    @Test func removedBlockTakesItsStateAway() async {
        let s = session(["a = 1"])
        s.setInput("x", for: s.blocks[0])
        s.update(blocks: [])
        s.update(blocks: [target(0, "a = 1")])
        #expect(s.input(for: s.blocks[0]) == "")
    }

    @Test func outputAndUnrunnableBlocksAreLeftOut() {
        let s = RunSession()
        var output = target(1, "42")
        output.language = nil
        output.tag = "output"
        var sql = target(2, "select 1")
        sql.language = .sql
        s.update(blocks: [target(0, "print(1)"), output, sql])
        #expect(s.blocks.count == 1)
    }

    @Test func failureIsRecordedAndCapUpdatesRunsLeft() async {
        let cap = RunCap(scope: .daily, runsLeft: 0, resetsAt: nil)
        let s = session(["a"], runner: StubRunner(error: .capped(cap)))
        s.run(transaction: "")
        await s.task?.value
        #expect(s.record(for: s.blocks[0])?.outcome == .failure(.capped(cap)))
        #expect(s.runsLeft == 0)
        #expect(!s.isRunning)
    }

    @Test func runSendsTheChosenBlocksInput() async {
        final class Box: @unchecked Sendable { var job: RunJob? }
        let box = Box()
        struct Spy: CodeRunning {
            var box: Box
            func run(_ job: RunJob) async throws -> RunResult { box.job = job; return RunResult(status: .ok) }
        }
        let s = session(["a", "b"], runner: Spy(box: box))
        s.choose(s.blocks[1])
        s.setInput("7 8", for: s.blocks[1])
        s.run(transaction: "jws")
        await s.task?.value
        #expect(box.job?.code == "b")
        #expect(box.job?.stdin == "7 8")
        #expect(box.job?.transaction == "jws")
    }

    @Test func statusLines() {
        #expect(RunPresentation.statusLine(RunResult(status: .ok, timeSeconds: 0.02, memoryKB: 3174)) == "Finished · 0.02s · 3.1MB")
        #expect(RunPresentation.statusLine(RunResult(status: .compileError)) == "Compile error")
        #expect(RunPresentation.statusLine(RunResult(status: .timeLimit)) == "Time limit")
    }

    @Test func dockWidthClamps() {
        #expect(RunDockWidth.clamped(100, available: 1200) == 280)
        #expect(RunDockWidth.clamped(900, available: 1200) == 600)
        #expect(RunDockWidth.clamped(360, available: 400) == 280)
    }
}

/// A runner that answers when the test says so, one job at a time.
actor GatedRunner: CodeRunning {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var answers: [String] = []

    func run(_ job: RunJob) async throws -> RunResult {
        await withCheckedContinuation { waiting.append($0) }
        return RunResult(status: .ok, stdout: job.code, runsLeft: nil)
    }

    var pending: Int { waiting.count }

    func release(_ index: Int) { waiting[index].resume() }
}

@MainActor
@Suite struct RunSessionInFlightTests {
    private func target(_ ordinal: Int, _ code: String) -> CodeBlockTarget {
        CodeBlockTarget(
            id: CodeBlockID(ordinal: ordinal, code: code),
            range: NSRange(location: 0, length: code.utf16.count),
            language: .python, code: code, tag: "python"
        )
    }

    private func waitForPending(_ gate: GatedRunner, _ count: Int) async throws {
        for _ in 0..<2000 {
            if await gate.pending >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("the runner was never asked for job \(count)")
        throw CancellationError()
    }

    /// The running block is deleted and another takes its place; the first
    /// run's answer must not land on the second block.
    @Test func aRunWhoseBlockWasRemovedDoesNotAnswerForTheNextRun() async throws {
        let gate = GatedRunner()
        let s = RunSession()
        s.defaults = RunSessionTests.defaults()
        s.runner = gate
        s.update(blocks: [target(0, "first")])
        s.run(transaction: "jws")
        let firstTask = s.task
        try await waitForPending(gate, 1)

        s.update(blocks: [target(0, "second")])   // "first" is gone
        s.run(transaction: "jws")
        try await waitForPending(gate, 2)

        await gate.release(0)                      // the first run answers late
        await firstTask?.value
        #expect(s.record(for: s.blocks[0]) == nil)
        #expect(s.isRunning)                       // the second is still going

        await gate.release(1)
        await s.task?.value
        guard case .result(let result)? = s.record(for: s.blocks[0])?.outcome else {
            Issue.record("no result for the second run"); return
        }
        #expect(result.stdout == "second")
    }
}

/// QC R3: the reader is told where code goes before the first run sends it.
@MainActor
@Suite("The first run's notice") struct RunDisclosureTests {
    private func session(_ codes: [String], runner: any CodeRunning = StubRunner(), disclosed: Bool = true) -> RunSession {
        let s = RunSession()
        s.defaults = RunSessionTests.defaults(disclosed: disclosed)
        s.runner = runner
        s.update(blocks: codes.enumerated().map { ordinal, code in
            CodeBlockTarget(
                id: CodeBlockID(ordinal: ordinal, code: code),
                range: NSRange(location: 0, length: code.utf16.count),
                language: .python, code: code, tag: "python"
            )
        })
        return s
    }

    @Test("The first run is held for the notice; nothing reaches the service until the reader agrees")
    func firstRunIsHeld() async {
        let runner = CountingRunner()
        let s = session(["print(1)"], runner: runner, disclosed: false)
        s.tab = .input
        s.run(transaction: "jws")
        #expect(s.awaitsDisclosure)
        #expect(!s.isRunning)
        #expect(s.tab == .output, "the notice is on the Output tab")
        #expect(runner.runs == 0)

        s.acceptDisclosure()
        await s.task?.value
        #expect(!s.awaitsDisclosure)
        #expect(runner.runs == 1)
        #expect(s.record(for: s.blocks[0]) != nil)
        #expect(RunDisclosure.isAccepted(in: s.defaults))
    }

    @Test("Not Now sends nothing, and the next Run asks again")
    func notNow() {
        let runner = CountingRunner()
        let s = session(["print(1)"], runner: runner, disclosed: false)
        s.run(transaction: "jws")
        s.declineDisclosure()
        #expect(!s.awaitsDisclosure)
        #expect(runner.runs == 0)
        #expect(!RunDisclosure.isAccepted(in: s.defaults))
        s.run(transaction: "jws")
        #expect(s.awaitsDisclosure)
    }

    @Test("Once agreed, it is remembered: another note's session runs at once")
    func remembered() async {
        let defaults = RunSessionTests.defaults(disclosed: false)
        let first = session(["print(1)"], disclosed: false)
        first.defaults = defaults
        first.run(transaction: "jws")
        first.acceptDisclosure()
        await first.task?.value

        let runner = CountingRunner()
        let second = session(["print(2)"], runner: runner)
        second.defaults = defaults
        second.run(transaction: "jws")
        #expect(!second.awaitsDisclosure)
        await second.task?.value
        #expect(runner.runs == 1)
    }
}
