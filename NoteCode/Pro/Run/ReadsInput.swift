//
//  ReadsInput.swift
//  NoteCode
//
//  Whether a program reads standard input, so the Output tab can say "this
//  program waits for input" before the student wonders why nothing printed.
//  A guess from the source, never a reason to refuse a run.
//

import Foundation

nonisolated enum ReadsInput {
    static func check(_ code: String, language: CodeLanguage) -> Bool {
        guard let pattern = patterns[language] else { return false }
        return code.range(of: pattern, options: .regularExpression) != nil
    }

    private static let patterns: [CodeLanguage: String] = [
        .cpp:        #"\bcin\b|\b(?:getline|scanf|fscanf|getchar|fgets|gets)\s*\("#,
        .c:          #"\b(?:scanf|fscanf|getchar|fgets|gets|getline|getc)\s*\("#,
        .java:       #"\bSystem\s*\.\s*in\b"#,
        .python:     #"\binput\s*\(|\bsys\s*\.\s*stdin\b"#,
        .javascript: #"\breadline\b|\bprocess\s*\.\s*stdin\b|/dev/stdin|readFileSync\s*\(\s*0\b"#,
        .rust:       #"\bstdin\s*\(|\bread_line\s*\("#,
        .go:         #"\bos\s*\.\s*Stdin\b|\bfmt\s*\.\s*Scan(?:ln|f)?\s*\("#,
    ]
}
