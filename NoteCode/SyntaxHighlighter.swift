//
//  SyntaxHighlighter.swift
//  NoteCode
//
//  The seam between the editor and whatever colours the code.
//

#if canImport(UIKit)

import UIKit

/// Which appearance the colours should suit.
///
/// Passed in rather than read inside the highlighter so the decision happens
/// once, on the main actor, alongside everything else that reads traits.
enum HighlightAppearance: Equatable {
    case light
    case dark

    init(_ traits: UITraitCollection) {
        self = traits.userInterfaceStyle == .dark ? .dark : .light
    }
}

/// A span of code to paint, with offsets relative to the code string that was
/// handed in — not to the document. The caller adds the block's offset.
struct ColorRun: Equatable {
    var range: NSRange
    var color: UIColor
}

/// Anything that can colour a snippet of code.
///
/// Exists so the editor never imports a highlighting library directly. Swapping
/// implementations, or dropping highlighting entirely, means changing which
/// object gets constructed — the editor keeps working either way, falling back
/// to the plain monospace styling that DocumentStyler already applies.
protocol SyntaxHighlighter {
    func colorRuns(
        for code: String,
        language: CodeLanguage,
        appearance: HighlightAppearance
    ) async -> [ColorRun]
}

#endif
