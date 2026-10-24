//
//  MarkerDimming.swift
//  NoteCode
//
//  Settings › Writing › Markers: how dim each kind of visible marker is.
//

import Foundation

/// How a kind of marker shows: not at all, dimmed (today's look), or in the
/// text's own colour.
nonisolated enum MarkerLevel: String, CaseIterable, Sendable {
    case off, dim, full

    var title: String {
        switch self {
        case .off:  "Off"
        case .dim:  "Dim"
        case .full: "Full"
        }
    }
}

/// How dim the four kinds of visible marker are, per device (feedback item 9).
///
/// The markers that take part are the ones the app draws or colours:
/// the hashes of a heading shown in the margin, a list's bullets and
/// numbers, a checkbox's outline, and a code block's fence lines (the
/// backticks and tag, while they show). **Off hides the marker without
/// changing a line's layout** (its colour is clear, or it isn't drawn), as
/// Show Markdown's hiding does, so a setting never moves a word from under
/// its ink. Bold, italic, code and link marks are always hidden and aren't
/// here.
///
/// Four settings that reach the styler and two fragments together, so they
/// travel as one value and `DocumentTextView.updateUIView` applies them with
/// one call (`apply(to:in:)`), as `CodeEditorSettings` does. The default is
/// the look before there were settings: everything `dim`.
nonisolated struct MarkerDimming: Equatable, Sendable {

    var headings = MarkerLevel.dim
    var bullets = MarkerLevel.dim
    var checkboxes = MarkerLevel.dim
    var fences = MarkerLevel.dim

    static let standard = MarkerDimming()

    static let headingsKey = "markerDimming.headings"
    static let bulletsKey = "markerDimming.bullets"
    static let checkboxesKey = "markerDimming.checkboxes"
    static let fencesKey = "markerDimming.fences"
}

#if canImport(UIKit)
import UIKit

extension MarkerDimming {

    /// A heading's hashes in the margin: `nil` for off, which draws none.
    var headingColour: UIColor? {
        switch headings {
        case .off:  nil
        case .dim:  .secondaryLabel
        case .full: .label
        }
    }

    /// A heading's marker characters in the text itself, which a rendered
    /// note collapses to no width: tertiary as every marker's colour is.
    var headingTextColour: UIColor {
        colour(headings, dim: DocumentStyler.markerColor, full: .label)
    }

    /// A list item's bullet or number.
    var bulletColour: UIColor {
        colour(bullets, dim: .tertiaryLabel, full: .label)
    }

    /// An unchecked box's outline: `nil` for off, which draws none. A checked
    /// box is the accent filled, which is the item's state and not a marker
    /// to dim.
    var checkboxColour: UIColor? {
        switch checkboxes {
        case .off:  nil
        case .dim:  .tertiaryLabel
        case .full: .label
        }
    }

    /// A code block's fence lines, shown while it is edited or always. On an
    /// output block's dark panel they take that panel's own colours.
    func fenceColour(isOutput: Bool) -> UIColor {
        isOutput
            ? colour(fences, dim: CodeOutputPanel.labelColor, full: CodeOutputPanel.textColor)
            : colour(fences, dim: .tertiaryLabel, full: .label)
    }

    private func colour(_ level: MarkerLevel, dim: UIColor, full: UIColor) -> UIColor {
        switch level {
        case .off:  .clear
        case .dim:  dim
        case .full: full
        }
    }

    /// Hands the settings to the editor's coordinator, which acts on a change
    /// and ignores a repeat.
    @MainActor
    func apply(to coordinator: DocumentTextView.Coordinator, in textView: DocumentUITextView) {
        coordinator.setMarkerDimming(self, in: textView)
    }
}

extension DocumentTextView.Coordinator {

    /// A new setting restyles the note, whose marker colours change, and
    /// redraws the fragments that draw a marker themselves.
    func setMarkerDimming(_ new: MarkerDimming, in textView: UITextView) {
        guard new != markerDimming else { return }
        markerDimming = new
        invalidateStyling()
        restyle(textView)
        Self.redraw(fragmentViewsIn: textView, intersecting: textView.bounds.insetBy(dx: -50, dy: -50))
    }
}

#endif
