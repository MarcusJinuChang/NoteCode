//
//  PencilResponse.swift
//  NoteCode
//
//  What a double tap or squeeze of the Pencil does in ink mode.
//

#if canImport(UIKit)

import SwiftUI

/// What the app does for a Pencil gesture, from what the reader chose for it
/// in Settings › Apple Pencil.
///
/// The choice is the reader's, not the app's: Apple asks apps to honour it,
/// and someone who set double tap to "switch to previous tool" in every
/// other app would find it switching to the eraser here. Out of the box,
/// double tap switches to the eraser and squeeze shows the tool palette.
enum PencilResponse: Equatable {
    /// Swap between the current tool and the eraser.
    case toggleEraser
    /// Swap between the current tool and the one before it.
    case switchToPreviousTool
    /// Show the ink tools and their options beside the Pencil.
    case showInkTools
    /// Nothing for the app to do: turned off, or a system shortcut, which
    /// the system runs itself.
    case nothing

    init(_ preferred: PencilPreferredAction) {
        switch preferred {
        case .switchEraser:
            self = .toggleEraser
        case .switchPrevious:
            self = .switchToPreviousTool
        // The palette has the colours, the sizes and the tools, so it
        // answers all three of the system's palette choices.
        case .showColorPalette, .showInkAttributes, .showContextualPalette:
            self = .showInkTools
        default:
            self = .nothing
        }
    }
}

#endif
