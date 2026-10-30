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

/// Settings › General › App Icon: the Default icon and the two alternates.
///
/// The choice isn't stored by the app. iOS keeps it
/// (`UIApplication.alternateIconName`) and brings it back at every launch, so
/// a second copy in `UserDefaults` could only disagree with what the Home
/// Screen shows. This type is the names and colours; the setter is the
/// picker in SettingsView.
///
/// The names are the asset catalog's icon sets and must match
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in the target, and the
/// colours must match `scripts/make-icons.swift`, which draws the art
/// (`AppIconTests` checks both against the built app and the PNGs).
nonisolated enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case standard
    case paper
    case orange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default"
        case .paper:    "Paper"
        case .orange:   "Orange"
        }
    }

    /// What `setAlternateIconName` takes. `nil` is the primary icon, `AppIcon`.
    var alternateIconName: String? {
        switch self {
        case .standard: nil
        case .paper:    "AppIcon-Paper"
        case .orange:   "AppIcon-Orange"
        }
    }

    /// The choice that is showing, from the name the system reports. A name
    /// this build doesn't know, say from a later build's alternate, reads as
    /// the Default, since that is what a missing icon falls back to.
    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .standard
    }

    /// The icon's three colours as RGB hex, on the design's Logo board.
    var background: Int {
        switch self {
        case .standard: 0x141416
        case .paper:    0xFFFFFF
        case .orange:   0xFA8500
        }
    }

    var brackets: Int {
        switch self {
        case .standard: 0xFFFFFF
        case .paper:    0x141416
        case .orange:   0xFFFFFF
        }
    }

    var pencil: Int {
        switch self {
        case .standard: 0xFA8500
        case .paper:    0xFA8500
        case .orange:   0x141416
        }
    }
}

/// Settings › Help and About: where the reader can reach the developer, and
/// what build this is.
nonisolated enum AppInfo {

    /// Our run proxy (`server/run-proxy/`), which Run in the app talks to. With
    /// `nil` Run in the app doesn't exist: no In NoteCode choice, no Pro gate on
    /// the run button, no panel. Never a Judge0 address or key; the proxy owns those.
    static let runService: URL? = URL(string: "https://notecode-run-proxy.changm2608.workers.dev")

    /// Where Send Feedback writes to. `nil` until there is an address to
    /// publish, and the row is left out until then: a mail button that opens
    /// a message to nobody is the kind of placeholder App Review rejects.
    static let feedbackAddress: String? = nil

    /// The privacy policy's page (the `gh-pages` branch's `privacy.md`; its
    /// text is drafted in `docs/site/privacy.md`). Never optional: the
    /// paywall and the App Store both need the link to exist.
    static let privacyPolicy = URL(string: "https://marcusjinuchang.github.io/NoteCode/privacy")!

    /// The `mailto:` link for Send Feedback, or `nil` without an address.
    static func feedbackURL(address: String? = feedbackAddress) -> URL? {
        mail(to: address, subject: "NoteCode Feedback")
    }

    /// The `mailto:` link for Feature Request, at the list's foot: the same
    /// address under its own subject, so requests can be told from reports
    /// in the inbox. `nil` without an address, like Send Feedback.
    static func featureRequestURL(address: String? = feedbackAddress) -> URL? {
        mail(to: address, subject: "NoteCode Feature Request")
    }

    private static func mail(to address: String?, subject: String) -> URL? {
        guard let address, !address.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
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
    /// Puts the pen's and the highlighter's palettes back to the colours of
    /// `set` (the device's own by default), in the defaults the hotbar reads
    /// them from.
    ///
    /// Only the palettes: the colour each tool is drawing in is left alone,
    /// and falls back to the palette's first colour on its own if the reset
    /// took it away (`InkSwatches`). Choosing a set is `InkPaletteSet.apply`.
    nonisolated static func resetStoredPalettes(
        to set: InkPaletteSet? = nil,
        in defaults: UserDefaults = .standard
    ) {
        let set = set ?? .stored(in: defaults)
        for kind in [InkToolKind.pen, .highlighter] {
            set.resetPalette(for: kind, in: defaults)
        }
    }
}
