//
//  AIAssistant.swift
//  NoteCode
//
//  The state of one Explain or Summarise run, and the task that drives it.
//

import Foundation
import Observation

nonisolated enum AIFailure: Equatable, Sendable {
    case tooLong
    case declined
    case languageNotSupported
    case timedOut
    case empty
    case other

    var message: String {
        switch self {
        case .tooLong: "This is too long for the on-device model."
        case .declined: "The model wouldn't answer this one."
        case .languageNotSupported: "The model doesn't support this language."
        case .timedOut: "The model took too long. Try again."
        case .empty: "The model gave no answer. Try again."
        case .other: "The model couldn't finish. Try again."
        }
    }

    init(_ error: AIClientError) {
        switch error {
        case .contextTooLong: self = .tooLong
        case .declined: self = .declined
        case .languageNotSupported: self = .languageNotSupported
        case .timedOut: self = .timedOut
        case .failed: self = .other
        }
    }
}

nonisolated struct AIProgress: Equatable, Sendable {
    /// The answer so far, for a run that streams one.
    var partial: String
    /// Which model call this is, from 1, of how many.
    var step: Int
    var of: Int
}

nonisolated struct AIResult: Equatable, Sendable {
    var text: String
    /// Part of the text didn't fit, so the answer is about the rest.
    var wasTruncated: Bool
}

nonisolated enum AIState: Equatable, Sendable {
    case idle
    case unavailable(AIUnavailableReason)
    case generating(AIProgress)
    case done(AIResult)
    case failed(AIFailure)
}

/// Runs a job against a `TextModelClient` and reports where it is. One run at
/// a time: starting another cancels the first. Nothing is stored, and nothing
/// leaves the device (the client is the on-device model).
@MainActor
@Observable
final class AIAssistant {

    /// Set by `AIFeatureSettings.apply(to:)`.
    var settings = AIFeatureSettings()

    private(set) var state = AIState.idle

    /// The run the sheet is showing; the sheet is up while this is set.
    var job: AIJob?

    @ObservationIgnored let client: any TextModelClient
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped by every start and stop, so a task that was cancelled but is
    /// still unwinding can't write over a newer run.
    @ObservationIgnored private var generation = 0

    init(client: any TextModelClient) {
        self.client = client
    }

    var availability: AIAvailability {
        settings.isEnabled ? client.availability : .unavailable(.switchedOff)
    }

    /// Whether the menus offer the features at all.
    var offersFeatures: Bool {
        if case .unavailable(let reason) = availability, reason.hidesMenuItems { return false }
        return true
    }

    /// The context size jobs are cut for.
    var contextTokens: Int { client.contextTokens }

    func begin(_ job: AIJob) {
        stop()
        self.job = job

        if case .unavailable(let reason) = availability {
            state = .unavailable(reason)
            return
        }

        state = .generating(AIProgress(partial: "", step: 1, of: job.stepCount))
        generation += 1
        let mine = generation
        task = Task { [weak self] in
            await self?.run(job, generation: mine)
        }
    }

    /// Stops generating and leaves the sheet's job where it is.
    func cancel() {
        guard case .generating = state else { return }
        stop()
        state = .idle
    }

    /// Closes the sheet.
    func dismiss() {
        stop()
        job = nil
        state = .idle
    }

    private func stop() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private func run(_ job: AIJob, generation mine: Int) async {
        func isCurrent() -> Bool { mine == generation && !Task.isCancelled }

        do {
            var partials: [String] = []
            let steps = job.stepCount
            for index in job.chunks.indices {
                let request = AIPrompts.request(for: job, piece: index)
                let answer = try await consume(request, step: index + 1, of: steps, isCurrent: isCurrent)
                guard isCurrent() else { return }
                partials.append(answer)
            }

            var answer = partials[0]
            if job.chunks.count > 1 {
                answer = try await consume(AIPrompts.combine(partials, for: job), step: steps, of: steps, isCurrent: isCurrent)
            }
            guard isCurrent() else { return }

            let text = AIInsertion.cleaned(answer)
            state = text.isEmpty ? .failed(.empty) : .done(AIResult(text: text, wasTruncated: job.wasTruncated))
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent() else { return }
            state = .failed((error as? AIClientError).map(AIFailure.init) ?? .other)
        }
    }

    /// One model call: shows each snapshot as it arrives and returns the last.
    private func consume(_ request: AIRequest, step: Int, of steps: Int, isCurrent: () -> Bool) async throws -> String {
        var latest = ""
        for try await snapshot in client.stream(request) {
            guard isCurrent() else { throw CancellationError() }
            latest = snapshot
            // Partial notes on a piece of a long note aren't the answer, so
            // only the final call shows its text.
            state = .generating(AIProgress(partial: step == steps ? latest : "", step: step, of: steps))
        }
        return latest
    }
}
