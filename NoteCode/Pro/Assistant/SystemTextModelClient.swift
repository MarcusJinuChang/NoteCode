//
//  SystemTextModelClient.swift
//  NoteCode
//
//  Apple's on-device model behind `TextModelClient`. The only file that
//  imports FoundationModels, so the rest of the assistant builds and is
//  tested without a model (docs/design/ai-features.md).
//
//  On-device only: `SystemLanguageModel.default`. Never
//  `PrivateCloudComputeLanguageModel`, which sends the prompt to Apple's
//  servers and would make "nothing is collected" untrue.
//

#if canImport(FoundationModels)

import FoundationModels
import Foundation

nonisolated struct SystemTextModelClient: TextModelClient {

    var availability: AIAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale() ? .available : .unavailable(.languageNotSupported)
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled: return .unavailable(.appleIntelligenceOff)
            case .modelNotReady: return .unavailable(.modelNotReady)
            @unknown default: return .unavailable(.modelNotReady)
            }
        }
    }

    /// The model's context window, or the 4,096 tokens every release before 27
    /// had when it can't say: a simulator without the model's assets reports 0.
    var contextTokens: Int {
        let size = SystemLanguageModel.default.contextSize
        return size >= 1_000 ? size : 4_096
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // A session per request: no transcript carries one note's
                    // text into the next, and the context never fills up.
                    let session = LanguageModelSession(model: .default, instructions: request.instructions)
                    let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: request.maximumResponseTokens)
                    for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: Self.classify(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// What the model's errors mean to the sheet. Anything not named is a
    /// plain failure: the reader is told to try again, never shown a type.
    static func classify(_ error: any Error) -> AIClientError {
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .contextTooLong
            case .guardrailViolation, .refusal: return .declined
            case .unsupportedLanguageOrLocale: return .languageNotSupported
            case .timeout: return .timedOut
            default: return .failed
            }
        }
        return .failed
    }
}

#endif

extension AIAssistant {
    /// The assistant the app uses: Apple's on-device model. Where the
    /// framework is missing every request reports the model unavailable.
    static func system() -> AIAssistant {
        AIAssistant(client: systemClient, isPro: { ProStatus.shared.isPro })
    }

    /// The device's model, for Settings to read without an assistant.
    static var systemClient: any TextModelClient {
#if canImport(FoundationModels)
        SystemTextModelClient()
#else
        NoTextModel()
#endif
    }
}

/// Stands in where FoundationModels doesn't exist.
nonisolated struct NoTextModel: TextModelClient {
    var availability: AIAvailability { .unavailable(.deviceNotEligible) }
    var contextTokens: Int { 4096 }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: AIClientError.failed) }
    }
}
