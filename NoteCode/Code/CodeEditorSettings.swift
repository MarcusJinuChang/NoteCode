//
//  CodeEditorSettings.swift
//  NoteCode
//
//  Settings › Code, as the editor needs them: one value, one place that hands
//  it to the editor.
//

import Foundation

/// What Settings › Code sets for typing and showing code, per device.
///
/// Three settings that all reach the editor, so they travel as one value and
/// `DocumentTextView.updateUIView` applies them with one call
/// (`apply(to:in:)`), and none can be set on its own and forgotten at a call
/// site. `TextRewritingPolicy` is the reference example for this.
nonisolated struct CodeEditorSettings: Equatable, Sendable {

    /// Spaces in one level: 2 or 4.
    var indentWidth = CodeIndent.defaultWidth

    /// The row of keys above the on-screen keyboard while the caret is in code.
    var codeKeys = CodeKeys.enabledByDefault

    /// Numbers beside each line of code, in the page's margin.
    var lineNumbers = LineNumbers.enabledByDefault
}

/// Settings › Code › Line Numbers.
nonisolated enum LineNumbers {
    static let defaultsKey = "lineNumbers"
    static let enabledByDefault = false
}

#if canImport(UIKit)
import UIKit

extension CodeEditorSettings {
    /// Hands the settings to the editor's coordinator, which acts on a change
    /// and ignores a repeat.
    @MainActor
    func apply(to coordinator: DocumentTextView.Coordinator, in textView: DocumentUITextView) {
        coordinator.indentWidth = CodeIndent.validWidth(indentWidth)
        coordinator.setCodeKeys(codeKeys, in: textView)
        coordinator.setLineNumbers(lineNumbers, in: textView)
    }
}
#endif
