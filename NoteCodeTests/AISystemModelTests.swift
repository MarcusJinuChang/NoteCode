//
//  AISystemModelTests.swift
//  NoteCodeTests
//
//  The real model, as far as a test run can reach it. Availability depends on
//  the machine (the simulator inherits the Mac's Apple Intelligence), so these
//  record what they find and only demand what holds everywhere.
//

#if canImport(FoundationModels)

import Foundation
import FoundationModels
import Testing
@testable import NoteCode

@Suite("System model client")
struct AISystemModelTests {

    @Test("Reading availability and the context size never traps, whatever state the machine is in")
    func availabilityIsReported() {
        let client = SystemTextModelClient()
        let availability = client.availability
        print("AI-PROBE availability:", availability, "contextTokens:", client.contextTokens,
              "languages:", SystemLanguageModel.default.supportedLanguages.count)
        // The simulator without the model's assets reports a context size of
        // 0 (measured 24 Oct); the client must not pass that on.
        #expect(client.contextTokens >= 1_000)
    }

    @Test("What the raw model throws where it can't generate, so the mapping is built on fact")
    func rawError() async {
        do {
            let session = LanguageModelSession(model: .default, instructions: "Say hi.")
            for try await _ in session.streamResponse(to: "Hi", options: GenerationOptions(maximumResponseTokens: 20)) {}
            print("AI-PROBE raw: generated")
        } catch {
            print("AI-PROBE raw error:", type(of: error), String(describing: error).prefix(300))
            print("AI-PROBE classified:", SystemTextModelClient.classify(error))
        }
    }

    @Test("When the model is available it streams a non-empty answer; when not, the app says why")
    func smoke() async throws {
        let client = SystemTextModelClient()
        guard client.availability == .available else {
            print("AI-PROBE smoke skipped: model unavailable")
            return
        }
        var last = ""
        var snapshots = 0
        defer { print("AI-PROBE smoke ended with", snapshots, "snapshots") }
        let request = AIRequest(
            instructions: AIPrompts.explainInstructions(length: .brief),
            prompt: AIPrompts.explainPrompt(code: "int add(int a, int b) { return a + b; }", languageName: "C++", cut: false),
            maximumResponseTokens: 160
        )
        do {
            for try await snapshot in client.stream(request) {
                snapshots += 1
                last = snapshot
            }
        } catch {
            // "Available" is read from the host; a simulator without the
            // model's assets cannot generate. That is a failure the sheet
            // words, not a crash.
            #expect(error is AIClientError)
            print("AI-PROBE smoke failed with", error)
            return
        }
        print("AI-PROBE smoke answer:", last)
        #expect(!last.isEmpty)
    }

    @Test("Model errors map to the failures the sheet words")
    func classification() {
        #expect(SystemTextModelClient.classify(CancellationError()) == .failed)
        #expect(SystemTextModelClient.classify(AIClientError.declined) == .failed)
    }
}

#endif
