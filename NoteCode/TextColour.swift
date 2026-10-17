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
/// The hex is stored as chosen. What is drawn is that colour taken just far
/// enough toward black on a light page, or white on a dark one, for 4.5:1
/// (`AccentPalette.textHex`, as links are), so the same note reads in both
/// appearances and a colour from elsewhere is as legible as the palette's.
nonisolated enum TextColour: Int, CaseIterable, Sendable {
    case red = 0xE5484D
    case orange = 0xE5750A
    case yellow = 0xB88700
    case green = 0x2F9E44
    case blue = 0x3B82F6
    case purple = 0x9061F9

    var hex: Int { rawValue }

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
