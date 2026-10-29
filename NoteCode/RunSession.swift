//
//  RunSession.swift
//  NoteCode
//
//  The Run panel's state for one open note: which block is chosen, what was
//  typed as input for each, and the last result of each. No UI and no UIKit,
//  so the rules about staleness and about surviving edits are testable alone.
//  docs/release-1.0/R-run.md › R3.
//

import Foundation
import Observation

/// A block the panel can run.
nonisolated struct RunBlock: Equatable, Sendable, Identifiable {
    var id: CodeBlockID
    var language: CodeLanguage
    var code: String
    /// UTF-16 offset of the opening fence, for scrolling the note to it.
    var location: Int

    var ordinal: Int { id.ordinal }
}

/// What a run came to: the program's result, or why there was none.
nonisolated enum RunOutcome: Equatable, Sendable {
    case result(RunResult)
    case failure(RunServiceError)
}

/// An outcome and the code it was for.
nonisolated struct RunRecord: Equatable, Sendable {
    var outcome: RunOutcome
    var ranHash: UInt64
}

@MainActor
@Observable
final class RunSession {
    enum Tab: Equatable { case output, input }

    /// Blocks that can run, in document order.
    private(set) var blocks: [RunBlock] = []

    /// Results and input are kept by the block's ordinal; `update(blocks:)`
    /// moves them when blocks come and go above.
    private var records: [Int: RunRecord] = [:]
    private var inputs: [Int: String] = [:]
    private var chosenOrdinal: Int?

    private(set) var runningOrdinal: Int?
    /// The code the running job was started with, and which run it is, so an
    /// edit can cancel it and a late answer can be told from the current one.
    private var runningHash: UInt64?
    private var runGeneration = 0
    private(set) var runsLeft: Int?

    /// Where code goes. `nil` hides Run altogether (`RunServiceFactory`).
    @ObservationIgnored var runner: (any CodeRunning)?
    /// Told when the service refuses the subscription (a 402).
    @ObservationIgnored var onNotSubscribed: (() -> Void)?
    /// Hands a block to the page's site instead: the panel's button for an
    /// offline phone, a used-up day or a service that is down. Set by the
    /// text view's coordinator, which knows the site.
    @ObservationIgnored var openAtSite: ((RunBlock) -> Void)?
    /// Keep in Note: writes the text under the block with that ordinal.
    @ObservationIgnored var keepInNote: ((Int, String) -> Void)?
    /// A compile-error link: the caret to a 1-based line of the block.
    @ObservationIgnored var showLine: ((RunBlock, Int) -> Void)?

    var isOpen = false
    var isCollapsed = false
    var tab = Tab.output

    @ObservationIgnored private(set) var task: Task<Void, Never>?

    var isAvailable: Bool { runner != nil }

    /// The chosen block, or the first when none is chosen or it is gone.
    var chosen: RunBlock? {
        blocks.first { $0.ordinal == chosenOrdinal } ?? blocks.first
    }

    var isRunning: Bool { runningOrdinal != nil }

    func choose(_ block: RunBlock) {
        chosenOrdinal = block.ordinal
    }

    func record(for block: RunBlock) -> RunRecord? {
        records[block.ordinal]
    }

    /// The result no longer matches the block's code.
    func isStale(_ block: RunBlock) -> Bool {
        guard let record = records[block.ordinal] else { return false }
        return record.ranHash != block.id.contentHash
    }

    func input(for block: RunBlock) -> String {
        inputs[block.ordinal] ?? ""
    }

    func setInput(_ text: String, for block: RunBlock) {
        inputs[block.ordinal] = text.isEmpty ? nil : text
    }

    // MARK: Edits

    /// Takes the note's blocks after an edit.
    func update(blocks targets: [CodeBlockTarget]) {
        let new = targets.compactMap { target -> RunBlock? in
            guard !target.isOutput, let language = target.language, language.canRun else { return nil }
            return RunBlock(id: target.id, language: language, code: target.code, location: target.range.location)
        }
        guard new != blocks else { return }
        let map = Self.remap(from: blocks.map(\.id), to: new.map(\.id))
        func moved<T>(_ old: [Int: T]) -> [Int: T] {
            var result: [Int: T] = [:]
            for (ordinal, value) in old {
                if let to = map[ordinal] { result[to] = value }
            }
            return result
        }
        records = moved(records)
        inputs = moved(inputs)
        chosenOrdinal = chosenOrdinal.flatMap { map[$0] }
        runningOrdinal = runningOrdinal.flatMap { map[$0] }
        blocks = new
        // A run for code that is gone or was edited answers for nothing.
        if let ordinal = runningOrdinal, let hash = runningHash,
           new.first(where: { $0.ordinal == ordinal })?.id.contentHash != hash {
            abandonRun()
        } else if runningOrdinal == nil, task != nil, runningHash != nil {
            abandonRun()
        }
    }

    /// Where each old block went, by ordinal. A block whose code is unchanged
    /// is followed to wherever it is now (nearest first, so a pair of equal
    /// blocks keep their order); one that was edited in place stays at its
    /// ordinal; one that was removed, or edited as the list changed, is
    /// dropped.
    nonisolated static func remap(from old: [CodeBlockID], to new: [CodeBlockID]) -> [Int: Int] {
        var map: [Int: Int] = [:]
        var taken = Set<Int>()
        for id in old {
            let best = new
                .filter { $0.contentHash == id.contentHash && !taken.contains($0.ordinal) }
                .min { abs($0.ordinal - id.ordinal) < abs($1.ordinal - id.ordinal) }
            if let best {
                map[id.ordinal] = best.ordinal
                taken.insert(best.ordinal)
            }
        }
        for id in old where map[id.ordinal] == nil {
            if new.contains(where: { $0.ordinal == id.ordinal }), !taken.contains(id.ordinal) {
                map[id.ordinal] = id.ordinal
                taken.insert(id.ordinal)
            }
        }
        return map
    }

    // MARK: Running

    /// Runs the chosen block. `transaction` is the subscription's signed
    /// transaction (`ProStatus.signedTransaction`).
    func run(transaction: String) {
        guard let runner, let block = chosen, !isRunning else { return }
        let job = RunJob(
            language: block.language, code: block.code,
            stdin: input(for: block), transaction: transaction
        )
        let hash = block.id.contentHash
        chosenOrdinal = block.ordinal
        runningOrdinal = block.ordinal
        runningHash = hash
        runGeneration += 1
        let mine = runGeneration
        task = Task { [weak self] in
            let outcome: RunOutcome?
            do {
                outcome = .result(try await runner.run(job))
            } catch is CancellationError {
                outcome = nil
            } catch let error as RunServiceError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.serviceDown)
            }
            self?.finish(outcome, hash: hash, generation: mine)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func abandonRun() {
        task?.cancel()
        runGeneration += 1
        runningOrdinal = nil
        runningHash = nil
    }

    private func finish(_ outcome: RunOutcome?, hash: UInt64, generation: Int) {
        // Not this run's turn any more: it was abandoned, or another began.
        guard generation == runGeneration else { return }
        defer { runningOrdinal = nil; runningHash = nil }
        guard let ordinal = runningOrdinal, let outcome else { return }
        records[ordinal] = RunRecord(outcome: outcome, ranHash: hash)
        switch outcome {
        case .result(let result):
            if let left = result.runsLeft { runsLeft = left }
        case .failure(.capped(let cap)):
            runsLeft = cap.runsLeft ?? 0
        case .failure(.notSubscribed):
            onNotSubscribed?()
        case .failure:
            break
        }
    }
}

// MARK: - What the panel says

nonisolated enum RunPresentation {
    /// The line above the output: "Finished · 0.02s · 3.1MB".
    static func statusLine(_ result: RunResult) -> String {
        var parts: [String]
        switch result.status {
        case .ok: parts = ["Finished"]
        case .compileError: parts = ["Compile error"]
        case .runtimeError(let exitCode, let signal):
            if let signal { parts = ["Stopped by signal \(signal)"] }
            else if let exitCode { parts = ["Exited with code \(exitCode)"] }
            else { parts = ["Runtime error"] }
        case .timeLimit: parts = ["Time limit"]
        case .memoryLimit: parts = ["Memory limit"]
        case .serviceError: parts = ["Run service error"]
        }
        if let time = result.timeSeconds { parts.append(String(format: "%.2fs", time)) }
        if let kb = result.memoryKB {
            parts.append(kb >= 1024 ? String(format: "%.1fMB", Double(kb) / 1024) : "\(kb)KB")
        }
        return parts.joined(separator: " · ")
    }

    /// Whether the panel offers to open the block on a site: when the service
    /// can't run it right now. Not for a refused subscription (the paywall
    /// opens) nor a block too large for the service, which a site may take.
    static func offersSite(after error: RunServiceError) -> Bool {
        switch error {
        case .offline, .capped, .serviceDown, .tooLarge: true
        case .notSubscribed: false
        }
    }

    static func message(for error: RunServiceError) -> String {
        switch error {
        case .offline: "You're offline. Run needs a connection."
        case .notSubscribed: "Your NoteCode Pro subscription wasn't accepted."
        case .capped(let cap):
            switch cap.scope {
            case .daily: "You've used today's runs."
            case .perMinute: "Too many runs in a minute. Try again shortly."
            case .global: "Run is busy today. Try again later."
            }
        case .tooLarge: "The code or its input is too large to run."
        case .serviceDown: "The run service isn't answering. Try again in a moment."
        }
    }
}

// MARK: - The runner the app uses

enum RunServiceFactory {
    /// The client for `AppInfo.runService`, or `nil` when there is none, and
    /// with it no Run control. The debug stub outranks it so the panel can be
    /// seen without a proxy.
    @MainActor static func make(service: URL? = AppInfo.runService) -> (any CodeRunning)? {
#if DEBUG
        if let kind = DebugLaunchOptions.current.runStub { return DebugRunStub(kind: kind) }
#endif
        return service.map { RunServiceClient(baseURL: $0) }
    }
}

#if DEBUG
nonisolated enum DebugRunStubKind: String, CaseIterable, Sendable {
    case ok, compileError = "compile-error", runtimeError = "runtime-error"
    case timeLimit = "time-limit", capped
}

/// Canned answers for `-debug-run-stub`, so the panel can be seen without a proxy.
nonisolated struct DebugRunStub: CodeRunning {
    var kind: DebugRunStubKind

    func run(_ job: RunJob) async throws -> RunResult {
        try await Task.sleep(for: .milliseconds(400))
        switch kind {
        case .ok:
            return RunResult(status: .ok, stdout: "Hello, NoteCode\n42\n", timeSeconds: 0.02, memoryKB: 3174, runsLeft: 18)
        case .compileError:
            return RunResult(
                status: .compileError,
                compileOutput: "main.cpp:5:3: error: use of undeclared identifier 'cout'\n  cout << x;\n  ^\n",
                runsLeft: 17
            )
        case .runtimeError:
            return RunResult(
                status: .runtimeError(exitCode: 1, signal: nil), stdout: "before\n",
                stderr: "terminate called after throwing an instance of 'std::out_of_range'\n",
                timeSeconds: 0.01, memoryKB: 2900
            )
        case .timeLimit:
            return RunResult(status: .timeLimit, stdout: "1\n2\n3\n", timeSeconds: 5.0, memoryKB: 2048)
        case .capped:
            throw RunServiceError.capped(RunCap(scope: .daily, runsLeft: 0, resetsAt: nil))
        }
    }
}
#endif
