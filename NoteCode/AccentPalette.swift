//
//  AccentPalette.swift
//  NoteCode
//
//  Settings › General › Accent Colour: the colour of controls, the caret and
//  selection, the checked box, the selected row and links. Pure, so the
//  stored value and the contrast rules are tested without a view.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The reader's accent, per device like the dock and the appearance.
///
/// Stored as six hex digits (`FA8500`) under `defaultsKey`; nothing stored
/// means the design's orange, which is the `AccentColor` asset and keeps its
/// Increase Contrast variants. A value that isn't six hex digits reads as
/// nothing stored, so a bad write can't leave the app without an accent.
///
/// Only one colour is stored, for both appearances. What changes with the
/// appearance is the colour used as *text*: links need 4.5:1 against the
/// page, and a chosen colour is darkened (light) or lightened (dark) just far
/// enough to get it (`textHex`). The default keeps the design's own pair.
nonisolated enum AccentPalette {

    static let defaultsKey = "accentColor"

    /// The design's orange, `#FA8500`.
    static let defaultHex = 0xFA8500

    /// The design's text pair for the default accent: the Increase Contrast
    /// slots of `AccentColor`.
    private static let defaultTextLight = 0xB85900
    private static let defaultTextDark = 0xFFAA33

    // MARK: Stored value

    /// The chosen colour, or `nil` for the default.
    static func customHex(in defaults: UserDefaults = .standard) -> Int? {
        parse(defaults.string(forKey: defaultsKey))
    }

    /// The accent in use: the chosen colour or the default.
    static func hex(in defaults: UserDefaults = .standard) -> Int {
        customHex(in: defaults) ?? defaultHex
    }

    /// `nil` for the default; a stored value that is orange itself is the
    /// default too, so choosing it back needs no special case.
    static func parse(_ stored: String?) -> Int? {
        guard let stored, stored.count == 6, let value = Int(stored, radix: 16) else { return nil }
        return value == defaultHex ? nil : value
    }

    static func string(for hex: Int) -> String {
        String(format: "%06X", hex & 0xFFFFFF)
    }

    /// A picker's colour as 24-bit sRGB, clamped.
    @MainActor
    static func hex(of color: Color) -> Int {
        var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        #if canImport(UIKit)
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .orange
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return (byte(red) << 16) | (byte(green) << 8) | byte(blue)
    }

    // MARK: Text and fills

    /// The accent as text on the page: links, in light or dark.
    static func textHex(for hex: Int, isDark: Bool) -> Int {
        if hex == defaultHex { return isDark ? defaultTextDark : defaultTextLight }
        let page = isDark ? 0x000000 : 0xFFFFFF
        // Toward black on a white page, toward white on a black one: the
        // colour keeps its hue and gets only as far as it must.
        let target = isDark ? 0xFFFFFF : 0x000000
        var amount = 0.0
        while amount < 1, contrast(mixed(hex, toward: target, by: amount), page) < 4.5 {
            amount += 0.02
        }
        return mixed(hex, toward: target, by: min(amount, 1))
    }

    /// The link colour for the stored accent.
    static func linkHex(isDark: Bool, in defaults: UserDefaults = .standard) -> Int {
        textHex(for: hex(in: defaults), isDark: isDark)
    }

    /// Whether a label on a fill of this colour should be black. White is the
    /// design's (it is 2.6:1 on the orange, which the design accepts for
    /// 17pt semibold), so black is only for fills too light to carry it: under
    /// 2:1 against white.
    static func labelOnFillIsBlack(_ hex: Int) -> Bool {
        contrast(hex, 0xFFFFFF) < 2
    }

    // MARK: Contrast

    /// WCAG relative luminance of a 24-bit sRGB value.
    static func luminance(_ hex: Int) -> Double {
        let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { byte -> Double in
            let c = Double(byte) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    static func contrast(_ a: Int, _ b: Int) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    private static func mixed(_ hex: Int, toward target: Int, by amount: Double) -> Int {
        func channel(_ shift: Int) -> Int {
            let from = Double((hex >> shift) & 0xFF)
            let to = Double((target >> shift) & 0xFF)
            return Int((from + (to - from) * amount).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }
}

extension Color {
    /// The accent for code that holds a `Color` rather than a shape style.
    /// `Color.accentColor` ignores `.tint` (measured, `AccentPaletteTests`),
    /// so this reads the stored value; the default is the asset, with its
    /// Increase Contrast variants.
    static func accent(stored: String) -> Color {
        AccentPalette.parse(stored).map { Color(hex: $0) } ?? .accentColor
    }
}

// MARK: - A button filled with the accent

/// Fills a shape with the tint and puts the label on it: white, the design's,
/// unless the chosen accent is too light to carry white
/// (`AccentPalette.labelOnFillIsBlack`).
private struct AccentFill<S: Shape>: ViewModifier {
    let shape: S
    @AppStorage(AccentPalette.defaultsKey) private var stored = ""

    func body(content: Content) -> some View {
        let black = AccentPalette.parse(stored).map(AccentPalette.labelOnFillIsBlack) ?? false
        content
            .foregroundStyle(black ? Color.black : Color.white)
            .background(.tint, in: shape)
    }
}

extension View {
    func accentFill<S: Shape>(in shape: S) -> some View {
        modifier(AccentFill(shape: shape))
    }
}

#if canImport(UIKit)

nonisolated extension AccentPalette {
    /// A colour from a 24-bit sRGB value.
    static func uiColor(_ hex: Int) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The accent to draw with where there is no view to ask for its tint: a
    /// checked box, which the PDF draws too. The chosen colour, or the asset
    /// for the default, so Increase Contrast still applies to it.
    static func drawingColor(in defaults: UserDefaults = .standard) -> UIColor {
        if let custom = customHex(in: defaults) { return uiColor(custom) }
        return UIColor(named: "AccentColor") ?? uiColor(defaultHex)
    }
}
#endif
