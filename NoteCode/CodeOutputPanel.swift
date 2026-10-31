//
//  CodeOutputPanel.swift
//  NoteCode
//
//  The colours of an output block: what a program printed, kept beside the
//  code that printed it.
//

#if canImport(UIKit)

import UIKit

/// A console, on the code panel's own colours: light in light mode, dark in
/// dark (31 Oct; it was a near-black panel in both, which sat as a black hole
/// on a white page). The label and "Output" still tell it from code.
///
/// The values are the system colours the code panel uses, resolved
/// (`secondarySystemBackground`, `label`, `secondaryLabel`), as plain hex so a
/// test can compute contrast. The text and the label are a hair off `.label`
/// and `.secondaryLabel` on purpose: the styler tells an output block's text
/// from default text by its colour (`DocumentStyler`), so it must be its own.
enum CodeOutputPanel {

    /// The tokens as hex, light then dark. Plain values so a test can read
    /// them without resolving a dynamic colour, and compute contrast.
    struct Tokens: Equatable {
        var fill: UInt32
        var text: UInt32
        var label: UInt32
    }

    static let light = Tokens(fill: 0xF2F2F7, text: 0x111113, label: 0x6C6C70)
    static let dark  = Tokens(fill: 0x1C1C1E, text: 0xF5F5F7, label: 0x98989D)

    static let fillColor  = dynamic(\.fill)
    static let textColor  = dynamic(\.text)
    /// The "Output" label and the fence lines while the block is being edited.
    static let labelColor = dynamic(\.label)
    /// The copy button, as on a code block: `.secondaryLabel`.
    static let controlColor = UIColor.secondaryLabel

    private static func dynamic(_ token: KeyPath<Tokens, UInt32>) -> UIColor {
        UIColor { traits in
            UIColor(hex: (traits.userInterfaceStyle == .dark ? dark : light)[keyPath: token])
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

#endif
