//
//  EditorSettings.swift
//  NoteCode
//
//  The settings `DocumentTextView` hands its coordinator, as one value with
//  one `apply(to:in:)`, so none can be set on its own and forgotten at a call
//  site (AGENTS.md › Conventions; `TextRewritingPolicy` is the reference).
//

#if canImport(UIKit)

import Foundation

/// What the editor's coordinator is told, apart from the note's text size
/// (`typography`, which is per note and applied inside `page.reflow`).
struct EditorSettings: Equatable {

    /// Settings › Writing › Show Markdown: whether a code block's backticks
    /// show only while it is being edited, or always.
    var showMarkdown = ShowMarkdown.whileEditing

    /// Settings › Writing › Markers: how dim the visible markers are.
    var markerDimming = MarkerDimming.standard

    /// Whether the note's Markdown markers take no room on the page
    /// (`Page.markdownLayout == rendered`). A legacy note keeps them visible,
    /// because its ink was drawn against that layout.
    var rendersMarkdown = false

    /// Settings › Code: indent width, the code-keys row, line numbers.
    var codeSettings = CodeEditorSettings()

    /// Settings › Writing › Autocorrect: whether prose is autocorrected and
    /// given smart punctuation (code never is).
    var rewritesProse = SettingKeys.Writing.autocorrectInProse.defaultValue

    /// Hands the settings to the coordinator in the order they have always
    /// been applied: rendering, typography, code, rewriting, markers. Each
    /// setter acts on a change and ignores a repeat.
    ///
    /// - Parameter typography: the note's text size, applied between
    ///   rendering and code when the editor is being made. `updateUIView`
    ///   passes `nil`: it applies a new size itself, inside `page.reflow`.
    @MainActor
    func apply(
        to coordinator: DocumentTextView.Coordinator,
        in textView: DocumentUITextView,
        typography: NoteTypography? = nil
    ) {
        coordinator.setRendersMarkdown(rendersMarkdown, in: textView)
        if let typography { coordinator.setTypography(typography, in: textView) }
        codeSettings.apply(to: coordinator, in: textView)
        coordinator.setRewritesProse(rewritesProse, in: textView)
        markerDimming.apply(to: coordinator, in: textView)
    }

    /// The Show Markdown mode, which is a plain property of the coordinator.
    /// Separate from `apply` because the two call sites set it at different
    /// points: `updateUIView` before the rest (a restyle in `apply` reads
    /// it), `makeUIView` after the first styling pass.
    @MainActor
    func applyShowMarkdown(to coordinator: DocumentTextView.Coordinator) {
        coordinator.showMarkdown = showMarkdown
    }
}

#endif
