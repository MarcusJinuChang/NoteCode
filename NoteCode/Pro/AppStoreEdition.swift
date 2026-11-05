//
//  AppStoreEdition.swift
//  NoteCode
//

import SwiftUI

/// The App Store edition: the general app with Pro, tips and ads.
/// The open-source build's `@main` is OpenSource/OpenSourceEdition.swift.
@main
struct NoteCodeApp: App {
    // Made once, when the app starts: the scene's init opens the store.
    private let scene: NoteCodeScene

    init() {
#if DEBUG
        // Before `.appStore`, whose TipJar.shared is the first to read the
        // launch arguments: a group set after that read isn't parsed.
        DebugLaunchOptions.editionGroups = [ProDebugOptions.self]
#endif
        scene = NoteCodeScene(extensions: .appStore)
    }

    var body: some Scene { scene }
}

extension AppExtensions {
    /// TipJar.shared is made first: it reads the launch arguments first
    /// (docs/refactor/2X-seam.md › Must not change). None of the three asks
    /// anything of its store or the ad stack when made.
    static let appStore = appStore(tipJar: .shared, pro: .shared, consent: .shared)

    /// The App Store edition over these objects; tests pass stand-ins.
    static func appStore(tipJar: TipJar, pro: ProStatus, consent: AdConsent) -> AppExtensions {
        var extensions = AppExtensions(
            start: {
                // Finishes tips that arrive outside a purchase, and asks the store
                // for the tips, so the list's foot knows whether to offer them.
                tipJar.start()
                // Reads whether the reader has Pro, and listens for renewals and refunds.
                pro.start()
            },
            root: { content in
                AnyView(content
                    .environment(tipJar)
                    .environment(pro))
            },
            // Below Home's page, not over it: Home's scroll view ends where
            // the ad starts, so nothing scrolls under it.
            homeFooter: { AnyView(AdSlot(placement: .home, opaque: true)) },
            homeAppeared: { await consent.homeAppeared(pro: pro) },
            listFootRows: { present in
                var rows: [ExtensionRow] = []
                // Guarded here too: an empty AdSlot would still be a blank row.
                if adBannerShows(isPro: pro.isPro, canRequestAds: consent.canRequestAds) {
                    rows.append(ExtensionRow(id: "ad") { AdSlot(placement: .list) })
                }
                // Once the App Store has answered with its products.
                if tipJar.isAvailable {
                    rows.append(ExtensionRow(id: "tipJar") {
                        Button {
                            present(ExtensionSheet(id: "tipJar") { TipJarView(jar: tipJar) })
                        } label: {
                            Label("Tip Jar", systemImage: "heart")
                        }
                        .accessibilityIdentifier("tipJarRow")
                    })
                }
                return rows
            },
            listFootAppeared: { tipJar.load() },
            aboutRows: {
                // Where the law lets the reader change their answer to
                // Google's consent form; UMP says where (AdConsent).
                guard consent.privacyOptionsRequired else { return [] }
                return [ExtensionRow(id: "adPrivacyOptions") {
                    Button("Ad Privacy Options") { Task { await consent.showPrivacyOptions() } }
                        .accessibilityIdentifier("adPrivacyOptionsButton")
                }]
            },
            settingsAppeared: { await consent.settingsAppeared(pro: pro) },
            // Not while a free reader's tracking prompt is still to come.
            mayAskForReview: { pro.isPro || consent.trackingAnswered },
            runLines: RunLines(
                note: "With NoteCode Pro, the run button runs it beside the page and shows what it prints.",
                screen: "NoteCode Pro runs it beside the page."))
        // Pro second in Settings' list; the assistant at the end of Writing.
        extensions.settingsSections = {
            [SettingsSection(id: "pro", placement: .afterGeneral) {
                NavigationLink { ProSettings() } label: { Label("Pro", systemImage: "star") }
            },
             SettingsSection(id: "assistant", placement: .writing) { AssistantSettingsSection() }]
        }
#if canImport(UIKit)
        // Explain Block, the options row's Explain and Summarise Note.
        extensions.editorFeatures = [AssistantFeature.factory()]
#endif
#if DEBUG
        extensions.debugResetKeys = [RunDisclosure.key]
        extensions.debugRoot = { AnyView($0.modifier(DebugPaywall())) }
#endif
        return extensions
    }
}
