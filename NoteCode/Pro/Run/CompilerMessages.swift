//
//  CompilerMessages.swift
//  NoteCode
//
//  Finds "file:line:col" in compile output and stderr, so R4 can turn each
//  into a link that puts the caret on that line of the block. The service
//  compiles the block's code as sent, so a line here is the block's own line.
//

import Foundation

nonisolated struct CompilerMessage: Equatable, Sendable {
    /// 1-based line within the block's code.
    var line: Int
    var column: Int?
    /// The text to make a link, as a range of the output's UTF-16 units.
    var range: NSRange
}

nonisolated enum CompilerMessages {
    /// Messages in order of appearance, one per distinct place in the output.
    /// Lines outside `1...lineCount` are dropped, when `lineCount` is given.
    static func find(in output: String, language: CodeLanguage, lineCount: Int? = nil) -> [CompilerMessage] {
        guard let pattern = patterns[language],
              let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else { return [] }
        let ns = output as NSString
        var found: [CompilerMessage] = []
        for m in regex.matches(in: output, range: NSRange(location: 0, length: ns.length)) {
            guard let line = Int(ns.substring(with: m.range(at: 1))), line >= 1 else { continue }
            if let lineCount, line > lineCount { continue }
            var column: Int?
            if m.numberOfRanges > 2, m.range(at: 2).location != NSNotFound {
                column = Int(ns.substring(with: m.range(at: 2)))
            }
            found.append(CompilerMessage(line: line, column: column, range: m.range(at: 0)))
        }
        return found
    }

    // Group 1 is the line, group 2 the column. Group 0 is what becomes the link.
    private static let patterns: [CodeLanguage: String] = [
        .cpp:        #"[\w./+-]+\.(?:cpp|cc|cxx|c|hpp|h):(\d+)(?::(\d+))?"#,
        .c:          #"[\w./+-]+\.(?:c|h):(\d+)(?::(\d+))?"#,
        .java:       #"[\w./-]+\.java:(\d+)()"#,
        .python:     #"\bline (\d+)()"#,
        .javascript: #"[\w./-]+\.(?:js|mjs):(\d+)(?::(\d+))?"#,
        .rust:       #"-->\s*[\w./-]+\.rs:(\d+):(\d+)"#,
        .go:         #"[\w./-]+\.go:(\d+):(\d+)"#,
    ]
}
