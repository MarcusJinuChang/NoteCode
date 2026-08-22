//
//  FenceParser.swift
//  NoteCode
//
//  Pure fence detection. No UIKit, no SwiftUI, no TextKit — this file turns a
//  document string into a list of regions and nothing else, so it stays cheap
//  to unit-test (see AGENTS.md, "Conventions").
//

import Foundation

// MARK: - Language

/// A language a fenced code block can be tagged with.
///
/// Only the three languages the app actually needs (CS133 C++, plus Java and
/// Python for algorithm practice). An unrecognized tag isn't an error — the
/// block still renders as code, it just has no language.
enum CodeLanguage: String, CaseIterable, Sendable {
    case cpp
    case java
    case python

    /// Maps what the user typed after the fence onto a known language.
    /// People write `c++`, `py`, `python3` — all of them should work.
    init?(tag: String) {
        switch tag.lowercased() {
        case "cpp", "c++", "cc", "cxx":       self = .cpp
        case "java":                          self = .java
        case "py", "python", "python3":       self = .python
        default:                              return nil
        }
    }

    /// The name the Piston API expects when Phase 3 sends this block off to run.
    var pistonName: String {
        switch self {
        case .cpp:    "c++"
        case .java:   "java"
        case .python: "python"
        }
    }
}

// MARK: - Regions

/// A fenced code block's metadata.
struct CodeBlock: Equatable, Sendable {
    /// Recognized language, or `nil` if the fence had no tag or an unknown one.
    var language: CodeLanguage?
    /// The raw text after the opening backticks, exactly as typed.
    var infoString: String
    /// `false` while the user is still typing and no closing fence exists yet.
    var isClosed: Bool
    /// Just the code between the fences — excludes both fence lines.
    /// This is what gets sent to Piston; `Region.range` is what gets styled.
    var contentRange: Range<String.Index>
}

/// One contiguous span of the document.
///
/// Regions are always returned in document order, are non-overlapping, and
/// together cover the entire string — so rendering can walk them start to
/// finish without worrying about gaps.
struct Region: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
        case code(CodeBlock)
    }

    var kind: Kind
    /// The whole span, fence lines included. Line-aligned: a region always
    /// starts at the beginning of a line and ends at the start of the next
    /// one, which is what makes drawing a block background straightforward.
    var range: Range<String.Index>

    var isCode: Bool {
        if case .code = kind { return true }
        return false
    }

    var codeBlock: CodeBlock? {
        if case .code(let block) = kind { return block }
        return nil
    }
}

// MARK: - Parser

enum FenceParser {

    /// Splits `text` into alternating prose and code regions.
    ///
    /// An unterminated fence deliberately produces a code region running to the
    /// end of the document — otherwise nothing would highlight until the user
    /// typed the closing fence, which AGENTS.md rules out.
    static func parse(_ text: String) -> [Region] {
        var regions: [Region] = []

        // `split` hands back Substrings whose indices point back into `text`,
        // so line boundaries double as document offsets for free.
        //
        // Splitting on `\.isNewline` rather than the literal "\n" matters: Swift
        // stores CRLF as a *single* Character (one grapheme cluster), so
        // `split(separator: "\n")` silently fails to break CRLF documents apart
        // and the whole file parses as one line.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        // Start of the prose run we haven't emitted yet.
        var pendingTextStart = text.startIndex
        // Set while we're inside a code block.
        var openFence: (start: String.Index, contentStart: String.Index, info: String, backticks: Int)?

        for (offset, line) in lines.enumerated() {
            let lineStart = line.startIndex
            // Start of the next line, i.e. this line including its terminator.
            let lineEnd = offset + 1 < lines.count ? lines[offset + 1].startIndex : text.endIndex

            let fence = fenceInfo(line)

            if let open = openFence {
                // Inside a block: only a bare fence of at least the opening
                // width closes it. A tagged fence is just code content.
                guard let fence, fence.info.isEmpty, fence.backticks >= open.backticks else { continue }

                regions.append(
                    Region(
                        kind: .code(
                            CodeBlock(
                                language: language(from: open.info),
                                infoString: open.info,
                                isClosed: true,
                                contentRange: open.contentStart..<lineStart
                            )
                        ),
                        range: open.start..<lineEnd
                    )
                )
                pendingTextStart = lineEnd
                openFence = nil
            } else if let fence {
                // Opening fence: flush whatever prose came before it.
                if pendingTextStart < lineStart {
                    regions.append(Region(kind: .text, range: pendingTextStart..<lineStart))
                }
                openFence = (start: lineStart, contentStart: lineEnd, info: fence.info, backticks: fence.backticks)
            }
        }

        // Whatever is left over when we run out of lines.
        if let open = openFence {
            regions.append(
                Region(
                    kind: .code(
                        CodeBlock(
                            language: language(from: open.info),
                            infoString: open.info,
                            isClosed: false,
                            contentRange: open.contentStart..<text.endIndex
                        )
                    ),
                    range: open.start..<text.endIndex
                )
            )
        } else if pendingTextStart < text.endIndex {
            regions.append(Region(kind: .text, range: pendingTextStart..<text.endIndex))
        }

        return regions
    }

    // MARK: Private

    private struct Fence {
        var backticks: Int
        var info: String
    }

    /// Recognizes a fence line: up to three spaces of indent, then three or
    /// more backticks, then an optional info string.
    ///
    /// Returns `nil` for ordinary prose — including lines containing inline
    /// code spans, since those don't *begin* with three backticks.
    private static func fenceInfo(_ line: Substring) -> Fence? {
        var cursor = line.startIndex

        var indent = 0
        while cursor < line.endIndex, line[cursor] == " ", indent < 4 {
            indent += 1
            cursor = line.index(after: cursor)
        }
        guard indent <= 3 else { return nil }

        var backticks = 0
        while cursor < line.endIndex, line[cursor] == "`" {
            backticks += 1
            cursor = line.index(after: cursor)
        }
        guard backticks >= 3 else { return nil }

        let info = line[cursor...].trimmingCharacters(in: .whitespaces)
        // A backtick in the info string means this is an inline code span on a
        // line of its own, not a fence.
        guard !info.contains("`") else { return nil }

        return Fence(backticks: backticks, info: info)
    }

    /// First whitespace-separated word of the info string, mapped to a language.
    private static func language(from infoString: String) -> CodeLanguage? {
        guard let tag = infoString.split(separator: " ").first else { return nil }
        return CodeLanguage(tag: String(tag))
    }
}
