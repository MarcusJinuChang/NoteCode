//
//  AppearanceModifier.swift
//  NoteCode
//
//  Settings › General › Appearance and Accent Colour, applied to a window (split out of SettingsView.swift).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Applies Settings › General › Appearance to a window's content.
///
/// At the root of the scene, so a change reaches every window, its sheets and
/// the UIKit controllers presented from it, the moment the setting changes.
///
/// **On UIKit it is the window's `overrideUserInterfaceStyle`, not
/// `preferredColorScheme`.** `preferredColorScheme` puts an override on each
/// controller SwiftUI presents, and giving it `nil` afterwards doesn't take it
/// off again: with the device in dark, Light and then System left the open
/// Settings sheet light under a dark page (13 Oct). A window's override can be
/// set back to `.unspecified`, and everything presented from the window,
/// sheets and pickers included, takes its traits from it.
///
/// It carries Settings › General › Accent Colour too, since that is the same
/// kind of thing: `.tint` for SwiftUI, and the window's `tintColor` for UIKit
/// (the caret, the selection, the Run button). The default sets neither, so
/// the `AccentColor` asset and its Increase Contrast variants apply as before.
struct AppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.default
    @AppStorage(AccentPalette.defaultsKey) private var accent = ""

    func body(content: Content) -> some View {
        let custom = AccentPalette.parse(accent)
        #if canImport(UIKit)
        content
            .tint(custom.map { Color(hex: $0) })
            .background(WindowAppearance(
                style: appearance.userInterfaceStyle,
                tint: custom.map { AccentPalette.uiColor($0) }
            ))
        #else
        content
            .tint(custom.map { Color(hex: $0) })
            .preferredColorScheme(appearance.colorScheme)
        #endif
    }
}

#if canImport(UIKit)

extension AppAppearance {
    /// `.unspecified` follows the system.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light:  .light
        case .dark:   .dark
        }
    }
}

/// Sets the override of the window it is in, now and whenever it changes
/// windows.
private struct WindowAppearance: UIViewRepresentable {
    var style: UIUserInterfaceStyle
    /// `nil` leaves the window's tint as the asset catalog's accent set it.
    var tint: UIColor?

    final class Anchor: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { apply() }
        }
        var windowTint: UIColor? {
            didSet { apply() }
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            appliedTint = false
            apply()
        }
        func apply() {
            guard let window else { return }
            if window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
            // Only on a change: a dynamic tint never compares equal to what
            // the window reports back, and `nil` hands the window back to the
            // app's accent.
            guard !appliedTint || lastTint != windowTint else { return }
            window.tintColor = windowTint
            lastTint = windowTint
            appliedTint = true
        }
        private var lastTint: UIColor?
        private var appliedTint = false
    }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        anchor.style = style
        anchor.windowTint = tint
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        anchor.style = style
        anchor.windowTint = tint
    }
}

#endif

extension AppAppearance {
    /// `nil` follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}
