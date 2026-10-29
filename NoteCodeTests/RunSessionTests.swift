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

    private func session(_ codes: [String], runner: any CodeRunning = StubRunner()) -> RunSession {
        let s = RunSession()
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
