//
//  AIFeaturesTests.swift
//  NoteCodeTests
//
//  Everything about the on-device assistant except the model: prompts, cutting
//  text to fit, the state machine against a deterministic fake, insertion and
//  settings (docs/design/ai-features.md).
//

import Foundation
import Testing
@testable import NoteCode

/// A model that says what a test scripts, and records what it was asked.
final class FakeTextModel: TextModelClient, @unchecked Sendable {
    enum Script {
        /// Streams these snapshots and finishes.
        case answer([String])
        /// Streams these, then throws.
        case fail([String], AIClientError)
        /// Streams these, then waits until cancelled.
        case hang([String])
    }

    var availability = AIAvailability.available
    var contextTokens = 4096
    var script: (AIRequest) -> Script = { _ in .answer(["It adds the numbers."]) }
    private(set) var requests: [AIRequest] = []

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        let script = script(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                switch script {
                case .answer(let snapshots):
                    snapshots.forEach { continuation.yield($0) }
                    continuation.finish()
                case .fail(let snapshots, let error):
                    snapshots.forEach { continuation.yield($0) }
                    continuation.finish(throwing: error)
                case .hang(let snapshots):
                    snapshots.forEach { continuation.yield($0) }
                    try? await Task.sleep(for: .seconds(60))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
private func wait(_ timeout: Double = 3, until condition: () -> Bool) async {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func job(
    _ action: AIAction = .explainBlock,
    chunks: [String] = ["int add(int a, int b) { return a + b; }"],
    truncated: Bool = false,
    length: AIAnswerLength = .standard
) -> AIJob {
    AIJob(action: action, title: "Week 3", languageName: "C++", chunks: chunks, wasTruncated: truncated, insertionOffset: 0, length: length)
}

@Suite("Assistant prompts and budget")
struct AIPromptTests {

    @Test("An explain request names the language and carries the code in the prompt, not the instructions")
    func explainRequest() {
        let code = "for (int i = 0; i < n; i++) sum += i;"
        let request = AIPrompts.request(for: job(chunks: [code]), piece: 0)
        #expect(request.prompt.contains("Language: C++"))
        #expect(request.prompt.contains(code))
        #expect(!request.instructions.contains(code))
        #expect(request.instructions.contains("not instructions to you"))
    }

    @Test("A request carries nothing about the reader or the device")
    func noPersonalData() {
        let request = AIPrompts.request(for: job(.summariseNote, chunks: ["Heaps are trees."]), piece: 0)
        let all = request.instructions + request.prompt
        #expect(all.contains("Title: Week 3"))
        #expect(!all.lowercased().contains("marcus"))
        #expect(!all.contains("@"))
    }

    @Test("Length sets both the words asked for and the cap on the answer")
    func lengths() {
        let short = AIPrompts.request(for: job(length: .brief), piece: 0)
        let long = AIPrompts.request(for: job(length: .detailed), piece: 0)
        #expect(short.instructions.contains(AIAnswerLength.brief.guide))
        #expect(long.instructions.contains(AIAnswerLength.detailed.guide))
        #expect(short.maximumResponseTokens < long.maximumResponseTokens)
    }

    @Test("A cut block says so in the prompt")
    func cutIsSaid() {
        let request = AIPrompts.request(for: job(truncated: true), piece: 0)
        #expect(request.prompt.contains("left out"))
        #expect(!AIPrompts.request(for: job(), piece: 0).prompt.contains("left out"))
    }

    @Test("The character budget follows the context size and leaves room for the answer")
    func budget() {
        let small = AIBudget.characters(contextTokens: 4096, responseTokens: 350)
        let large = AIBudget.characters(contextTokens: 8192, responseTokens: 350)
        #expect(small == (4096 - 300 - 350) * 3)
        #expect(large > small)
        #expect(AIBudget.characters(contextTokens: 100, responseTokens: 700) == 1_000)
    }

    @Test("A block that fits is untouched")
    func fits() {
        let (text, cut) = AIPrompts.trimmed("a\nb\nc", to: 100)
        #expect(text == "a\nb\nc")
        #expect(!cut)
    }

    @Test("A long block keeps its first lines and its last, whole, and marks the gap")
    func headAndTail() {
        let lines = (1...400).map { "line \($0)" }
        let (text, cut) = AIPrompts.trimmed(lines.joined(separator: "\n"), to: 1_000)
        #expect(cut)
        #expect(text.count <= 1_000)
        #expect(text.hasPrefix("line 1\nline 2"))
        #expect(text.hasSuffix("line 400"))
        #expect(text.contains(AIPrompts.omission))
        // Whole lines only.
        for line in text.split(separator: "\n") where line != Substring(AIPrompts.omission) {
            #expect(lines.contains(String(line)))
        }
    }

    @Test("One enormous line is cut by characters")
    func oneLine() {
        let (text, cut) = AIPrompts.trimmed(String(repeating: "x", count: 5_000), to: 1_000)
        #expect(cut)
        #expect(text.count <= 1_000)
    }

    @Test("An explain job is cut for the model's context")
    func explainJobCuts() {
        let code = (1...2_000).map { "stmt\($0);" }.joined(separator: "\n")
        let small = AIPrompts.explainJob(code: code, languageName: "C++", insertionOffset: 0, contextTokens: 4096, length: .standard)
        let large = AIPrompts.explainJob(code: code, languageName: "C++", insertionOffset: 0, contextTokens: 16_384, length: .standard)
        #expect(small.wasTruncated)
        #expect(small.chunks[0].count <= AIBudget.characters(contextTokens: 4096, responseTokens: 350))
        #expect(large.chunks[0].count > small.chunks[0].count)
    }

    @Test("A note that fits is one piece")
    func shortNote() {
        let (pieces, cut) = AIPrompts.chunks(of: "One.\n\nTwo.\n\nThree.", limit: 1_000)
        #expect(pieces == ["One.\n\nTwo.\n\nThree."])
        #expect(!cut)
    }

    @Test("A longer note is cut on blank lines into pieces that fit, in order")
    func chunking() {
        let paragraphs = (1...30).map { "Paragraph \($0) " + String(repeating: "w", count: 90) }
        let (pieces, cut) = AIPrompts.chunks(of: paragraphs.joined(separator: "\n\n"), limit: 1_000)
        #expect(!cut)
        #expect(pieces.count > 1)
        #expect(pieces.allSatisfy { $0.count <= 1_000 })
        #expect(pieces.joined(separator: "\n\n") == paragraphs.joined(separator: "\n\n"))
        // No paragraph is split between pieces.
        for paragraph in paragraphs {
            #expect(pieces.filter { $0.contains(paragraph) }.count == 1)
        }
    }

    @Test("Only the first pieces are used past the limit, and the job says so")
    func chunkLimit() {
        let paragraphs = (1...200).map { "Paragraph \($0) " + String(repeating: "w", count: 90) }
        let (pieces, cut) = AIPrompts.chunks(of: paragraphs.joined(separator: "\n\n"), limit: 1_000)
        #expect(cut)
        #expect(pieces.count == AIPrompts.maxChunks)
        #expect(pieces[0].hasPrefix("Paragraph 1 "))
    }

    @Test("A paragraph longer than a piece is cut on lines, then on characters")
    func longParagraph() {
        let lines = (1...100).map { "line \($0) " + String(repeating: "q", count: 40) }.joined(separator: "\n")
        let (byLines, _) = AIPrompts.chunks(of: lines, limit: 1_000)
        #expect(byLines.allSatisfy { $0.count <= 1_000 })
        #expect(byLines.allSatisfy { $0.hasPrefix("line ") })

        let (byCharacters, _) = AIPrompts.chunks(of: String(repeating: "z", count: 2_500), limit: 1_000)
        #expect(byCharacters.map(\.count) == [1_000, 1_000, 500])
    }

    @Test("A note's tags and layout characters are left out of what the model reads")
    func cleaning() {
        let text = "A <span style=\"color:#E5484D\">red</span> word\u{2060} and\u{200B} more"
        let cleaned = AIPrompts.clean(text)
        #expect(!cleaned.contains("<span"))
        #expect(!cleaned.contains("\u{2060}"))
        #expect(cleaned.contains("red"))
    }

    @Test("A summary job carries the title and the cut flag")
    func summaryJob() {
        let note = (1...800).map { "Paragraph \($0) " + String(repeating: "w", count: 90) }.joined(separator: "\n\n")
        let job = AIPrompts.summariseJob(text: note, title: "Week 3", insertionOffset: 5, contextTokens: 4096, length: .brief)
        #expect(job.title == "Week 3")
        #expect(job.wasTruncated)
        #expect(job.chunks.count == AIPrompts.maxChunks)
        #expect(job.stepCount == AIPrompts.maxChunks + 1)
        #expect(job.insertionOffset == 5)
    }
}

@Suite("Assistant state machine")
@MainActor
struct AIAssistantTests {

    private func assistant(_ model: FakeTextModel = FakeTextModel()) -> AIAssistant {
        AIAssistant(client: model)
    }

    @Test("It starts idle, streams, and ends done with the cleaned answer")
    func happyPath() async {
        let model = FakeTextModel()
        model.script = { _ in .answer(["It adds", "It adds two numbers.  \n\n\n"]) }
        let ai = assistant(model)
        #expect(ai.state == .idle)

        ai.begin(job())
        await wait { if case .done = ai.state { true } else { false } }

        #expect(ai.state == .done(AIResult(text: "It adds two numbers.", wasTruncated: false)))
        #expect(model.requests.count == 1)
        #expect(ai.job != nil)
    }

    @Test("While generating it shows the answer so far")
    func progress() async {
        let model = FakeTextModel()
        model.script = { _ in .hang(["Partial answer"]) }
        let ai = assistant(model)
        ai.begin(job())
        await wait { if case .generating(let p) = ai.state { p.partial == "Partial answer" } else { false } }
        #expect(ai.state == .generating(AIProgress(partial: "Partial answer", step: 1, of: 1)))
        ai.dismiss()
    }

    @Test("Unavailable: the model is never asked, and the reason is the model's")
    func unavailable() async {
        let model = FakeTextModel()
        model.availability = .unavailable(.appleIntelligenceOff)
        let ai = assistant(model)
        ai.begin(job())
        #expect(ai.state == .unavailable(.appleIntelligenceOff))
        #expect(model.requests.isEmpty)
        #expect(ai.offersFeatures)
    }

    @Test("Switched off in Settings: the model is never asked, and the menus leave the items out")
    func switchedOff() {
        let model = FakeTextModel()
        let ai = assistant(model)
        AIFeatureSettings(isEnabled: false).apply(to: ai)
        #expect(ai.availability == .unavailable(.switchedOff))
        #expect(!ai.offersFeatures)
        ai.begin(job())
        #expect(ai.state == .unavailable(.switchedOff))
        #expect(model.requests.isEmpty)
    }

    @Test("A device that can never run it hides the items; one that is only off for now does not")
    func whichReasonsHide() {
        #expect(AIUnavailableReason.deviceNotEligible.hidesMenuItems)
        #expect(AIUnavailableReason.switchedOff.hidesMenuItems)
        #expect(!AIUnavailableReason.appleIntelligenceOff.hidesMenuItems)
        #expect(!AIUnavailableReason.modelNotReady.hidesMenuItems)
        #expect(!AIUnavailableReason.languageNotSupported.hidesMenuItems)
        let model = FakeTextModel()
        model.availability = .unavailable(.deviceNotEligible)
        #expect(!assistant(model).offersFeatures)
    }

    @Test("Cancelling stops the run, goes idle, and a late snapshot changes nothing")
    func cancel() async {
        let model = FakeTextModel()
        model.script = { _ in .hang(["Half"]) }
        let ai = assistant(model)
        ai.begin(job())
        await wait { if case .generating(let p) = ai.state { !p.partial.isEmpty } else { false } }

        ai.cancel()
        #expect(ai.state == .idle)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(ai.state == .idle)
        #expect(ai.job != nil)
    }

    @Test("Dismissing closes the sheet and stops the run")
    func dismiss() async {
        let model = FakeTextModel()
        model.script = { _ in .hang([]) }
        let ai = assistant(model)
        ai.begin(job())
        ai.dismiss()
        #expect(ai.job == nil)
        #expect(ai.state == .idle)
    }

    @Test("A second run replaces the first, and only the second reports")
    func replaced() async {
        let model = FakeTextModel()
        var calls = 0
        model.script = { _ in
            calls += 1
            return calls == 1 ? .hang(["first"]) : .answer(["second"])
        }
        let ai = assistant(model)
        ai.begin(job())
        ai.begin(job())
        await wait { if case .done = ai.state { true } else { false } }
        #expect(ai.state == .done(AIResult(text: "second", wasTruncated: false)))
    }

    @Test("Each way a model can fail reads as its own failure")
    func failures() async {
        let cases: [(AIClientError, AIFailure)] = [
            (.contextTooLong, .tooLong), (.declined, .declined), (.languageNotSupported, .languageNotSupported),
            (.timedOut, .timedOut), (.failed, .other),
        ]
        for (error, failure) in cases {
            let model = FakeTextModel()
            model.script = { _ in .fail(["x"], error) }
            let ai = assistant(model)
            ai.begin(job())
            await wait { if case .failed = ai.state { true } else { false } }
            #expect(ai.state == .failed(failure))
        }
    }

    @Test("An answer with nothing in it is a failure, not a blank result")
    func emptyAnswer() async {
        let model = FakeTextModel()
        model.script = { _ in .answer([]) }
        let ai = assistant(model)
        ai.begin(job())
        await wait { if case .failed = ai.state { true } else { false } }
        #expect(ai.state == .failed(.empty))
    }

    @Test("A long note makes a call per piece and one to join them, and shows only the last")
    func longNote() async {
        let model = FakeTextModel()
        model.script = { request in
            request.instructions.contains("working notes") ? .answer(["notes on a part"]) : .answer(["The whole summary."])
        }
        let ai = assistant(model)
        ai.begin(job(.summariseNote, chunks: ["piece one", "piece two", "piece three"], truncated: true))
        await wait { if case .done = ai.state { true } else { false } }

        #expect(model.requests.count == 4)
        let combine = model.requests[3]
        #expect(combine.prompt.contains("Part 1:\nnotes on a part"))
        #expect(combine.prompt.contains("Part 3:\nnotes on a part"))
        #expect(combine.prompt.contains("too long"))
        #expect(ai.state == .done(AIResult(text: "The whole summary.", wasTruncated: true)))
    }

    @Test("Starting a long note reports the number of calls it will make")
    func steps() {
        let model = FakeTextModel()
        model.script = { _ in .hang([]) }
        let ai = assistant(model)
        ai.begin(job(.summariseNote, chunks: ["a", "b"]))
        #expect(ai.state == .generating(AIProgress(partial: "", step: 1, of: 3)))
        ai.dismiss()
    }
}

@Suite("Insert below")
struct AIInsertionTests {

    private func ranges(_ text: String) -> [CodeRange] {
        // The fenced block of these tests, as the parser would find it.
        let ns = text as NSString
        let open = ns.range(of: "```cpp")
        guard open.location != NSNotFound else { return [] }
        let close = ns.range(of: "```", range: NSRange(location: NSMaxRange(open), length: ns.length - NSMaxRange(open)))
        let end = close.location == NSNotFound ? ns.length : min(ns.length, NSMaxRange(ns.lineRange(for: close)))
        return [CodeRange(range: NSRange(location: open.location, length: end - open.location), isClosed: close.location != NSNotFound, language: .cpp, tag: "cpp")]
    }

    @Test("The anchor is the end of the code block the caret is in, else the end of the line")
    func anchors() {
        let text = "Intro line\n```cpp\nint x;\n```\nAfter\n"
        let blocks = ranges(text)
        #expect(AIInsertion.anchor(caret: 20, in: text as NSString, codeRanges: blocks) == ("Intro line\n```cpp\nint x;\n```\n" as NSString).length)
        #expect(AIInsertion.anchor(caret: 3, in: text as NSString, codeRanges: blocks) == 11)
        #expect(AIInsertion.anchor(caret: text.utf16.count, in: text as NSString, codeRanges: blocks) == text.utf16.count)
        let bare = "no newline at all"
        #expect(AIInsertion.anchor(caret: 4, in: bare as NSString, codeRanges: []) == bare.utf16.count)
    }

    @Test("A quote sits between blank lines, one `>` line to a line")
    func quote() {
        let text = "Intro\n```cpp\nint x;\n```\nAfter\n"
        let anchor = ("Intro\n```cpp\nint x;\n```\n" as NSString).length
        let edit = AIInsertion.edit(inserting: "First line.\n\nSecond.", style: .quote, at: anchor, in: text as NSString)
        #expect(edit?.applied(to: text) == "Intro\n```cpp\nint x;\n```\n\n> First line.\n>\n> Second.\n\nAfter\n")
    }

    @Test("At the end of a note with no final newline the quote starts on its own line")
    func atTheEnd() {
        let text = "Last line"
        let edit = AIInsertion.edit(inserting: "Answer.", style: .quote, at: text.utf16.count, in: text as NSString)
        #expect(edit?.applied(to: text) == "Last line\n\n> Answer.\n")
        #expect(edit?.selection.location == (edit!.applied(to: text) as NSString).length)
    }

    @Test("An output block is tagged output, and its fence is wider than any backticks in the answer")
    func output() {
        let text = "A\n"
        let plain = AIInsertion.edit(inserting: "It sums.", style: .output, at: 2, in: text as NSString)
        #expect(plain?.applied(to: text) == "A\n\n```output\nIt sums.\n```\n")

        let ticks = AIInsertion.edit(inserting: "Use ``` to fence.", style: .output, at: 2, in: text as NSString)
        #expect(ticks?.applied(to: text) == "A\n\n````output\nUse ``` to fence.\n````\n")
    }

    @Test("The inserted output parses as one output block")
    func outputParses() {
        let text = "A\n"
        let edit = AIInsertion.edit(inserting: "Line one.\nLine two.", style: .output, at: 2, in: text as NSString)!
        let result = edit.applied(to: text)
        let blocks = CodeBlockAction.targets(in: result, blocks: DocumentParser.parse(result))
        #expect(blocks.count == 1)
        #expect(blocks[0].isOutput)
        #expect(blocks[0].code.contains("Line two."))
    }

    @Test("The inserted quote parses as a quote")
    func quoteParses() {
        let text = "A\n"
        let result = AIInsertion.edit(inserting: "Said once.", style: .quote, at: 2, in: text as NSString)!.applied(to: text)
        let kinds = DocumentParser.parse(result).map { String(describing: $0.kind) }
        #expect(kinds.contains { $0.contains("blockQuote") })
    }

    @Test("An empty answer inserts nothing")
    func empty() {
        #expect(AIInsertion.edit(inserting: " \n\n ", style: .quote, at: 0, in: "A" as NSString) == nil)
    }

    @Test("An answer is cleaned: line ends, trailing space, runs of blank lines")
    func cleaning() {
        #expect(AIInsertion.cleaned("\n\nOne  \r\n\r\n\r\n\r\nTwo\t\n\n") == "One\n\nTwo")
    }
}

@Suite("Assistant settings")
struct AISettingsTests {

    @Test("Defaults: on, standard length, quotes")
    func defaults() {
        let settings = AIFeatureSettings()
        #expect(settings.isEnabled)
        #expect(settings.length == .standard)
        #expect(settings.insertStyle == .quote)
    }

    @Test("The stored names are pinned: renaming one orphans what a device saved")
    func keys() {
        #expect(AIFeatureSettings.enabledKey == "aiEnabled")
        #expect(AIFeatureSettings.lengthKey == "aiAnswerLength")
        #expect(AIFeatureSettings.insertStyleKey == "aiInsertStyle")
    }

    @Test("Stored values read back; ones the pickers couldn't write read as the defaults")
    func reading() {
        let suite = UserDefaults(suiteName: "AISettingsTests-\(UUID().uuidString)")!
        #expect(AIFeatureSettings(defaults: suite) == AIFeatureSettings())

        suite.set(false, forKey: AIFeatureSettings.enabledKey)
        suite.set("detailed", forKey: AIFeatureSettings.lengthKey)
        suite.set("output", forKey: AIFeatureSettings.insertStyleKey)
        #expect(AIFeatureSettings(defaults: suite) == AIFeatureSettings(isEnabled: false, length: .detailed, insertStyle: .output))

        suite.set("huge", forKey: AIFeatureSettings.lengthKey)
        suite.set("???", forKey: AIFeatureSettings.insertStyleKey)
        #expect(AIFeatureSettings(defaults: suite) == AIFeatureSettings(isEnabled: false))
    }

    @Test("One apply hands every setting to the assistant, and a new job uses its length")
    @MainActor
    func apply() {
        let ai = AIAssistant(client: FakeTextModel())
        AIFeatureSettings(isEnabled: false, length: .brief, insertStyle: .output).apply(to: ai)
        #expect(ai.settings == AIFeatureSettings(isEnabled: false, length: .brief, insertStyle: .output))
    }
}
