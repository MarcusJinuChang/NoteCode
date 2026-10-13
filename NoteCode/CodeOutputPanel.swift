//
//  CodeOutputPanel.swift
//  NoteCode
//
//  The colours of an output block: what a program printed, kept beside the
//  code that printed it.
//

#if canImport(UIKit)

import UIKit

/// A console. Dark in both appearances, which is the point: it reads as a
/// different kind of thing from the code above it, and as what a terminal
/// looks like. So none of these are `.label` or the code panel's fill.
///
/// The values are v3's design tokens (`Code` board): the light column is a
/// near-black panel with light text, the dark column lifts the panel to the
/// dark theme's grey so it still separates from a black page.
enum CodeOutputPanel {

    /// The tokens as hex, light then dark. Plain values so a test can read
    /// them without resolving a dynamic colour, and compute contrast.
    struct Tokens: Equatable {
        var fill: UInt32
        var text: UInt32
        var label: UInt32
    }

    static let light = Tokens(fill: 0x141416, text: 0xE5E5EA, label: 0xA1A1A6)
    static let dark  = Tokens(fill: 0x2C2C2E, text: 0xF2F2F7, label: 0x8E8E93)

    static let fillColor  = dynamic(\.fill)
    static let textColor  = dynamic(\.text)
    /// The "Output" label and the fence lines while the block is being edited.
    static let labelColor = dynamic(\.label)
    /// The copy button, a step lighter than the label so it reads as a
    /// control and not as part of it.
    static let controlColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0xC7C7CC)
            : UIColor(hex: 0xD1D1D6)
    }

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
