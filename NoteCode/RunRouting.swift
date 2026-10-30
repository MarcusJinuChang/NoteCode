//
//  RunRouting.swift
//  NoteCode
//
//  What a tap on Run does (the gate, then in the app or a site), and what
//  Keep in Note writes. Foundation only, so both are testable alone.
//  docs/archive/release-1.0/R-run.md › R4.
//

import Foundation

/// Where a Run tap goes.
nonisolated enum RunRoute: Equatable, Sendable {
    /// A free reader: the paywall opens and nothing else happens.
    case paywall
    /// Run in the panel.
    case inApp
    /// Hand the block to a site (today's redirect).
    case redirect

    /// - Parameters:
    ///   - hasRunner: there is a service to run on (`AppInfo.runService`).
    ///     Without one the app behaves as it did before R: no gate, no panel.
    ///   - isPro: `ProStatus.isPro`, the only thing read for the gate.
    ///   - destination: the page's resolved destination.
    static func route(hasRunner: Bool, isPro: Bool, destination: CodeDestination) -> RunRoute {
        guard hasRunner else { return .redirect }
        guard isPro else { return .paywall }
        return destination == .inApp ? .inApp : .redirect
    }
}

/// Writing a run's output into the note as an ```` ```output ```` block.
nonisolated enum KeepInNote {

    /// What a result is worth keeping: stdout, then compile output, then
    /// stderr, a blank line off each end. `nil` when there is nothing.
    static func text(of result: RunResult) -> String? {
        let parts = [result.stdout, result.compileOutput, result.stderr]
            .map { $0.replacingOccurrences(of: "\r\n", with: "\n") }
            .map { text -> String in
                var text = text
                while text.hasSuffix("\n") { text.removeLast() }
                return text
            }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// The edit that puts `output` directly under the code block at `ordinal`,
    /// or in place of the output block that already follows it (only blank
    /// lines between), so a second run replaces rather than duplicates.
    /// `nil` when the block isn't there.
    static func edit(
        output: String,
        forBlockAt ordinal: Int,
        in source: String,
        targets: [CodeBlockTarget]
    ) -> TextEdit? {
        guard let index = targets.firstIndex(where: { $0.id.ordinal == ordinal && !$0.isOutput }) else { return nil }
        let code = targets[index]
        let ns = source as NSString
        let end = NSMaxRange(code.range)

        let block = fenced(output)

        if targets.indices.contains(index + 1), targets[index + 1].isOutput {
            let next = targets[index + 1]
            let gap = ns.substring(with: NSRange(location: end, length: next.range.location - end))
            if gap.allSatisfy(\.isWhitespace) {
                let endsLine = ns.substring(with: next.range).hasSuffix("\n")
                let replacement = endsLine ? block + "\n" : block
                return TextEdit(
                    range: next.range, replacement: replacement,
                    selection: NSRange(location: next.range.location + (replacement as NSString).length, length: 0)
                )
            }
        }

        // The note's last line has no newline to put the block after.
        let lead = ns.substring(with: code.range).hasSuffix("\n") ? "" : "\n"
        let replacement = lead + block + "\n"
        return TextEdit(
            range: NSRange(location: end, length: 0), replacement: replacement,
            selection: NSRange(location: end + (replacement as NSString).length, length: 0)
        )
    }

    /// A fence longer than any run of backticks in the text, so output that
    /// holds a fence doesn't close its own block.
    static func fenced(_ text: String) -> String {
        var longest = 0, run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return fence + "output\n" + text + "\n" + fence
    }

    /// Where the caret goes for line `line` (1-based) of a block's code: the
    /// start of that line in the note. `nil` when the block has no such line.
    static func caretOffset(line: Int, in target: CodeBlockTarget, source: String) -> Int? {
        let ns = source as NSString
        guard line >= 1, NSMaxRange(target.range) <= ns.length else { return nil }
        // The code starts on the line after the opening fence.
        var location = NSMaxRange(ns.lineRange(for: NSRange(location: target.range.location, length: 0)))
        let lines = target.code.isEmpty ? 0 : target.code.split(separator: "\n", omittingEmptySubsequences: false).count
        guard line <= max(lines, 1) else { return nil }
        for _ in 1..<line {
            guard location < ns.length else { return nil }
            location = NSMaxRange(ns.lineRange(for: NSRange(location: location, length: 0)))
        }
        return location
    }
}

/// Where Run sends code, said once before the first run in the app and
/// agreed to with Run (App Review 5.1.1 and 5.1.2: the reader is told before
/// their text leaves the iPad). Says what the privacy page's "Running code
/// in the app" says.
nonisolated enum RunDisclosure {
    static let key = "runDisclosureAccepted"
    static let title = "Before your first run"
    static let message = "Run sends this block's code and its input to NoteCode's run service, which runs them on Judge0, an online code-execution service, and sends back the output. Nothing else in your notes is sent. Judge0 may keep what it runs for a while, so leave passwords and keys out of code you run."
    static let run = "Run"
    static let notNow = "Not Now"

    static func isAccepted(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    static func markAccepted(in defaults: UserDefaults) {
        defaults.set(true, forKey: key)
    }
}
