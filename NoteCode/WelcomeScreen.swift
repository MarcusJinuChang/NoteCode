//
//  WelcomeScreen.swift
//  NoteCode
//
//  The title screen a first launch opens with (the `Main` board).
//

import SwiftUI

/// The first thing a new reader sees: the mark, a line about what the app is,
/// three things it does, and Get Started.
///
/// Shown over the whole window on a first launch (`claimFirstLaunch`) and again
/// from Settings › Help and About. It's an overlay on `ContentView` rather than
/// a `fullScreenCover`, so that under Reduce Motion it can fade, which a cover's
/// own slide can't be told to do.
struct WelcomeScreen: View {
    /// Get Started: the screen goes, and Home is under it.
    var onGetStarted: () -> Void

    /// Whether the title screen has had its turn on this device. Set the first
    /// time it's asked, whether or not the screen was shown, and never cleared:
    /// like `WelcomeNote.madeKey`, so a launch that couldn't show it (storage
    /// in memory, a debug launch with a note of its own) doesn't owe it to the
    /// next one.
    static let shownKey = "welcomeScreenShown"

    /// Whether this launch should show the screen, claiming the turn.
    ///
    /// Not tied to the store being empty, as the Welcome note is: a build that
    /// updates over a semester of notes is the first time its reader sees the
    /// new home, and a title screen once is all that costs.
    static func claimFirstLaunch(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: shownKey) else { return false }
        defaults.set(true, forKey: shownKey)
        return true
    }

    /// The three rows. Plain data, so the words are read in one place.
    struct Feature: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let features = [
        Feature(
            symbol: "curlybraces",
            title: "Code that runs",
            detail: "Type ``` and a language for a highlighted block. NoteCode Pro runs it beside the page."
        ),
        Feature(
            symbol: "pencil.line",
            title: "Ink on the same page",
            detail: "Draw over text and code with Apple Pencil or a finger, then go back to typing."
        ),
        Feature(
            symbol: "doc.text",
            title: "Letter pages",
            detail: "Seamless, compressed or print layout, and any note shares as a PDF."
        ),
    ]

    static let tagline = "Notes for code, ink and pages"

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                card
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 48)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { DottedSurround() }
        // Everything behind it is out of reach until Get Started.
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("welcomeScreen")
    }

    private var card: some View {
        let isDark = colorScheme == .dark
        let orange = FolderColor.orange
        return VStack(spacing: 0) {
            NoteCodeMark()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 104 * 0.2237, style: .continuous))
                .accessibilityHidden(true)

            Text("NoteCode")
                .font(.system(size: 56, weight: .bold))
                .tracking(-0.03 * 56)
                .padding(.top, 24)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Text(Self.tagline)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 26) {
                ForEach(Self.features) { feature in
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(hex: orange.symbol(isDark: isDark)))
                            .frame(width: 48, height: 48)
                            .background(
                                Color(hex: orange.tint(isDark: isDark)),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.title)
                                .font(.headline)
                            Text(feature.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 44)

            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .accentFill(in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 48)
            .accessibilityIdentifier("getStartedButton")

            Text("Your notes stay on this iPad.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
        }
        .padding(.horizontal, 72)
        .padding(.top, 64)
        .padding(.bottom, 48)
        // The shadow is the card shape's own: on the stack it would shade the
        // text as well.
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(HomePalette.card)
                .shadow(color: .black.opacity(isDark ? 0.4 : 0.10), radius: 30, y: 24)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }
}

/// The colours Home and the title screen share. System colours, so each is its
/// own in light and dark: a light grey with white cards, and black with dark
/// grey ones.
enum HomePalette {
    static var background: Color {
#if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
#else
        Color(nsColor: .windowBackgroundColor)
#endif
    }

    static var card: Color {
#if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
#else
        Color(nsColor: .controlBackgroundColor)
#endif
    }

    static var separator: Color {
#if canImport(UIKit)
        Color(uiColor: .separator)
#else
        Color(nsColor: .separatorColor)
#endif
    }

    /// The dots of the title screen's backdrop.
    static var dot: Color {
#if canImport(UIKit)
        Color(uiColor: .systemGray4)
#else
        Color(nsColor: .separatorColor)
#endif
    }
}

/// The surround with a dot grid on it: the title screen's and the empty Home's
/// backdrop, the way a notebook's page looks. 24pt apart, 1.2pt in radius.
struct DottedSurround: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let radius: CGFloat = 1.2
            let color = HomePalette.dot
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(color)
                    )
                    x += spacing
                }
                y += spacing
            }
        }
        .background(HomePalette.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
