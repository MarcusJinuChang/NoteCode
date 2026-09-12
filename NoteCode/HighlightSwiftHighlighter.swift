//
//  HighlightSwiftHighlighter.swift
//  NoteCode
//
//  The only file in the app that knows HighlightSwift exists.
//

#if canImport(UIKit)

import SwiftUI
import UIKit
import HighlightSwift

/// Colours code with highlight.js, which HighlightSwift runs through
/// JavaScriptCore. Calls are async because that JS round trip is.
struct HighlightSwiftHighlighter: SyntaxHighlighter {

    private let highlight = Highlight()

    func colorRuns(
        for code: String,
        languageTag: String,
        appearance: HighlightAppearance
    ) async -> [ColorRun] {
        guard !code.isEmpty, !languageTag.isEmpty else { return [] }

        let colors: HighlightColors = switch appearance {
        case .light: .light(.xcode)
        case .dark:  .dark(.xcode)
        }

        // The String overload resolves highlight.js's own aliases, so any of
        // its ~56 languages works without NoteCode enumerating them. An
        // unrecognized tag throws, and the block simply stays plain.
        guard let highlighted = try? await highlight.attributedText(
            code,
            language: languageTag.lowercased(),
            colors: colors
        ) else {
            // A highlight failure is not an error worth surfacing — the code
            // simply stays plain monospace, which is a fine fallback.
            return []
        }

        // highlight.js trims whitespace off both ends of what it is handed, so
        // the attributed string coming back can be shorter than the code that
        // went in. Every run offset is then relative to that trimmed text. Used
        // as-is against the original they are all shifted left by however much
        // was removed from the front, which paints each token's colour one
        // character early and leaves the tail of the block uncoloured — the
        // "last letter never highlights" symptom.
        //
        // A block whose first line is blank is the common way to hit this,
        // because the newline after the opening fence is then part of the code.
        let trimmed = String(highlighted.characters)
        let source = code as NSString
        let offset: Int

        if trimmed == code {
            offset = 0
        } else {
            let found = source.range(of: trimmed)
            guard found.location != NSNotFound,
                  source.substring(to: found.location).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                // Came back altered in some way this can't map. Colouring by
                // these offsets would land on the wrong characters, which reads
                // as working syntax highlighting that is quietly wrong. Plain
                // monospace is the better failure.
                return []
            }
            offset = found.location
        }

        return highlighted.runs.compactMap { run in
            // HighlightSwift may populate either attribute scope depending on
            // how the AttributedString was built, so check both rather than
            // assuming. Reading only one silently yields no colour at all.
            // HighlightSwift populates the UIKit scope. Reading the bare
            // `run.foregroundColor` resolves to the SwiftUI scope whenever
            // SwiftUI is imported, which is always nil here — that silently
            // produced no colour at all. The SwiftUI branch is a fallback in
            // case a future version populates that scope instead.
            let color: UIColor? = if let uiKitColor = run.uiKit.foregroundColor {
                uiKitColor
            } else if let swiftUIColor = run.swiftUI.foregroundColor {
                UIColor(swiftUIColor)
            } else {
                nil
            }

            guard let color else { return nil }
            let range = NSRange(run.range, in: highlighted)
            return ColorRun(
                range: NSRange(location: range.location + offset, length: range.length),
                color: color
            )
        }
    }
}

#endif
