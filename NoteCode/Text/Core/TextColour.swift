//
//  TextColour.swift
//  NoteCode
//
//  Coloured text (roadmap step 10): the palette. How a colour is written is
//  `SpanStyle`.
//

import Foundation

/// A colour text can be set in. It is written in a run's tag (`SpanStyle`).
///
/// The hex is stored as chosen, and is what the note's tags keep, so it never
/// changes. What is drawn is `drawn`: a pair picked for each appearance, as
/// saturated as the hue allows at 4.5:1 or better on the page (21 Nov: the
/// stored hex taken toward black or white read washed out, on the page and
/// on the hotbar's swatches). A colour from elsewhere, not one of these, is
/// taken just far enough toward black or white for 4.5:1
/// (`AccentPalette.textHex`, as links are).
nonisolated enum TextColour: Int, CaseIterable, Sendable {
    case red = 0xE5484D
    case orange = 0xE5750A
    case yellow = 0xB88700
    case green = 0x2F9E44
    case blue = 0x3B82F6
    case purple = 0x9061F9

    var hex: Int { rawValue }

    /// What the colour is drawn in, on a light page and on a dark one. Each
    /// is 4.5:1 or better on its page (`AccentPaletteTests`).
    var drawn: (light: Int, dark: Int) {
        switch self {
        case .red:    (0xE0001A, 0xFF4D52)
        case .orange: (0xC25400, 0xFF8C1A)
        case .yellow: (0x986F00, 0xFFC92E)
        case .green:  (0x00862B, 0x30D158)
        case .blue:   (0x0062F0, 0x4C93FF)
        case .purple: (0x8B2CF5, 0xA66BFF)
        }
    }

    var name: String {
        switch self {
        case .red:    "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green:  "Green"
        case .blue:   "Blue"
        case .purple: "Purple"
        }
    }
}
