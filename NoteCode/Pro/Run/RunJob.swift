//
//  RunJob.swift
//  NoteCode
//
//  What the app asks the run service for, what comes back, and what can go
//  wrong on the way. Foundation only, so it compiles into a Mac CLI probe.
//  The wire format is docs/design/run-proxy-contract.md.
//

import Foundation

/// One block's program, ready to send.
nonisolated struct RunJob: Equatable, Sendable {
    var language: CodeLanguage
    var code: String
    var stdin: String
    /// The subscription's signed transaction (a StoreKit 2 JWS string). The
    /// caller supplies it, so the runner needs no StoreKit.
    var transaction: String

    init(language: CodeLanguage, code: String, stdin: String = "", transaction: String) {
        self.language = language
        self.code = code
        self.stdin = stdin
        self.transaction = transaction
    }
}

nonisolated struct RunResult: Equatable, Sendable {
    nonisolated enum Status: Equatable, Sendable {
        case ok
        case compileError
        /// The program ran and failed: a non-zero exit code, or a signal.
        case runtimeError(exitCode: Int?, signal: Int?)
        case timeLimit
        case memoryLimit
        /// The service ran, but the sandbox itself failed.
        case serviceError(String?)
    }

    var status: Status
    var stdout: String = ""
    var stderr: String = ""
    var compileOutput: String = ""
    var timeSeconds: Double?
    var memoryKB: Int?
    /// An output was cut at the proxy's cap.
    var truncated = false
    /// `X-Runs-Left`, when the service sent it.
    var runsLeft: Int?
    /// Java only: the class that held `main` was renamed to `Main` for the
    /// run, and this is its name in the note.
    var renamedJavaClass: String?
}

nonisolated enum RunServiceError: Error, Equatable, Sendable {
    /// No connection to the service.
    case offline
    /// The service refused the subscription (402).
    case notSubscribed
    case capped(RunCap)
    /// The code or the input is over the size limit (413).
    case tooLarge
    /// A 5xx, a timeout, or an answer the app can't read.
    case serviceDown
}

/// A 429: which limit was hit, and when it lifts.
nonisolated struct RunCap: Equatable, Sendable {
    nonisolated enum Scope: String, Equatable, Sendable {
        /// The subscription's runs for the day.
        case daily
        /// Too many requests from one address in a minute.
        case perMinute
        /// The service's own ceiling for the day, across everyone.
        case global
    }
    var scope: Scope
    var runsLeft: Int?
    var resetsAt: Date?
}
