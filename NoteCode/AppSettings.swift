//
//  AppSettings.swift
//  NoteCode
//
//  The settings that belong to no other type: how the app looks, whether the
//  hotbar clicks as it snaps, and the addresses and version About shows.
//  Pure, so the keys and the strings can be tested without a view.
//

import Foundation

/// Settings › General › Appearance.
///
/// Per device, like the dock and the view mode: it's how this reader likes
/// their screen, not part of any note. Applied once at the root of every
/// window (`AppearanceModifier`), so the page, the hotbar, the sheets and the
/// colour picker follow it together. The PDF ignores it and prints light.
nonisolated enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    static let `default` = AppAppearance.system
    static let defaultsKey = "appearance"

    var title: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }
}

/// Settings › General › Haptic on Snap: a tick as the hotbar lands on an edge.
nonisolated enum SnapHaptic {
    static let defaultsKey = "hapticOnSnap"
    static let isOnByDefault = true
}

/// Settings › Help and About: where the reader can reach the developer, and
/// what build this is.
nonisolated enum AppInfo {

    /// Where Send Feedback writes to. `nil` until there is an address to
    /// publish, and the row is left out until then: a mail button that opens
    /// a message to nobody is the kind of placeholder App Review rejects.
    static let feedbackAddress: String? = nil

    /// The privacy policy's page, which an upload requires. `nil` until it
    /// exists, and the row is left out until then.
    static let privacyPolicy: URL? = nil

    /// The `mailto:` link for Send Feedback, or `nil` without an address.
    static func feedbackURL(address: String? = feedbackAddress) -> URL? {
        guard let address, !address.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: "NoteCode Feedback")]
        return components.url
    }

    /// "1.0 (1)": the version the store shows, then the build.
    static func versionString(of bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil):    return version
        case let (nil, build?):      return "(\(build))"
        case (nil, nil):             return "Unknown"
        }
    }

    /// The licence text for the libraries in the app, bundled as
    /// `Acknowledgements.txt` (HighlightSwift's licence and highlight.js's).
    static func acknowledgements(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "Acknowledgements", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

extension EraserSettings {
    /// "Pixel, Medium": what Settings › Drawing › Eraser shows on its row.
    nonisolated var summary: String {
        switch mode {
        case .partial:     "Pixel, \(size.rawValue.capitalized)"
        case .wholeStroke: "Object"
        }
    }
}

extension InkPalette {
    /// Puts the pen's and the highlighter's palettes back to the design's
    /// colours, in the defaults the hotbar reads them from.
    ///
    /// Only the palettes: the colour each tool is drawing in is left alone,
    /// and falls back to the palette's first colour on its own if the reset
    /// took it away (`InkSwatches`).
    nonisolated static func resetStoredPalettes(in defaults: UserDefaults = .standard) {
        for kind in [InkToolKind.pen, .highlighter] {
            defaults.set(standard(for: kind).rawValue, forKey: defaultsKey(for: kind))
        }
    }
}
