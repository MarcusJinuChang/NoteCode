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
        language: CodeLanguage,
        appearance: HighlightAppearance
    ) async -> [ColorRun] {
        guard !code.isEmpty else { return [] }

        let colors: HighlightColors = switch appearance {
        case .light: .light(.xcode)
        case .dark:  .dark(.xcode)
        }

        guard let highlighted = try? await highlight.attributedText(
            code,
            language: language.highlightLanguage,
            colors: colors
        ) else {
            // A highlight failure is not an error worth surfacing — the code
            // simply stays plain monospace, which is a fine fallback.
            return []
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
            return ColorRun(range: NSRange(run.range, in: highlighted), color: color)
        }
    }
}

private extension CodeLanguage {
    /// Our three languages onto highlight.js's names.
    var highlightLanguage: HighlightLanguage {
        switch self {
        case .cpp:    .cPlusPlus
        case .java:   .java
        case .python: .python
        }
    }
}

#endif
