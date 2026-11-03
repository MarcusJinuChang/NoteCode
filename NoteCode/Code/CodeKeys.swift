//
//  CodeKeys.swift
//  NoteCode
//
//  The code-keys row: which keys it has, and when it is there. Pure; the
//  view is CodeKeysRow.swift.
//

import Foundation

/// One key on the row.
nonisolated enum CodeKey: Hashable, Sendable {
    /// ⇥ and ⇤: one level in or out on the lines the selection touches.
    case indent, outdent
    /// A character typed at the caret.
    case insert(String)
    /// ← and →: the caret one character, or a selection to its edge.
    case left, right

    /// The characters code needs and the iPad's keyboard buries two layers
    /// down, in the order the design lays them out.
    static let symbols: [CodeKey] = [
        "{", "}", "(", ")", "[", "]", "<", ">", ";", "=",
        "\"", "'", ":", "/", "\\", "|", "&", "*", "#",
    ].map(CodeKey.insert)

    /// Every key, left to right: the indent pair, the symbols, then the arrows.
    static let all: [CodeKey] = [.indent, .outdent] + symbols + [.left, .right]

    /// What the key shows.
    var title: String {
        switch self {
        case .indent:          "⇥"
        case .outdent:         "⇤"
        case .insert(let text): text
        case .left:            "←"
        case .right:           "→"
        }
    }

    /// What VoiceOver says. Punctuation read aloud as "left brace" and not
    /// as whatever the screen reader makes of a bare `{`.
    var accessibilityLabel: String {
        switch self {
        case .indent:  "Indent"
        case .outdent: "Outdent"
        case .left:    "Move left"
        case .right:   "Move right"
        case .insert(let text):
            [
                "{": "Left brace", "}": "Right brace", "(": "Left parenthesis", ")": "Right parenthesis",
                "[": "Left bracket", "]": "Right bracket", "<": "Less than", ">": "Greater than",
                ";": "Semicolon", "=": "Equals", "\"": "Double quote", "'": "Single quote",
                ":": "Colon", "/": "Slash", "\\": "Backslash", "|": "Vertical bar",
                "&": "Ampersand", "*": "Asterisk", "#": "Number sign",
            ][text] ?? text
        }
    }
}

extension CodeKey: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .insert(value) }
}

/// Where the row is, and which keys it holds.
nonisolated enum CodeKeys {

    /// Settings › Code › Code Keys. Per device; on until turned off.
    static let enabledKey = "codeKeys"
    static let enabledByDefault = true

    /// The keys for where the caret is: all of them in code, none in prose.
    ///
    /// "In code" is `TextRewritingPolicy`'s answer, the one the keyboard's
    /// autocorrect already switches on, so the row and the traits can't
    /// disagree about where code is: a fenced block's lines and its fences,
    /// inline code, and a backtick or a fence still being typed.
    static func keys(for policy: TextRewritingPolicy) -> [CodeKey] {
        switch policy {
        case .code:                CodeKey.all
        case .prose, .proseWithoutRewriting: []
        }
    }

    /// Whether the row is on the keyboard.
    ///
    /// Not with a hardware keyboard, which has these keys. Not in a note that
    /// can't be edited, which has no keyboard at all. Not when the reader
    /// turned it off.
    ///
    /// The hardware keyboard is asked last, and only when the rest says yes:
    /// this is decided on every caret move.
    static func isShown(
        enabled: Bool,
        policy: TextRewritingPolicy,
        hardwareKeyboard: @autoclosure () -> Bool,
        isEditable: Bool
    ) -> Bool {
        enabled && isEditable && !keys(for: policy).isEmpty && !hardwareKeyboard()
    }
}
