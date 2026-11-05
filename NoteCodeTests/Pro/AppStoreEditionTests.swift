//
//  AppStoreEditionTests.swift
//  NoteCodeTests
//
//  What the App Store edition adds through the slots (`AppExtensions.appStore`).
//

import Foundation
import Testing
@testable import NoteCode

@Suite("App Store edition", .serialized, .tags(.pro))
@MainActor
struct AppStoreEditionTests {

    private func defaults() -> UserDefaults {
        let name = "AppStoreEditionTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func jarWithTips() async -> TipJar {
        let jar = TipJar(store: TipJarTests.FakeStore(tips: TipJarTests.three))
        jar.load()
        await jar.loaded()
        return jar
    }

    @Test("A free reader's list foot: the ad, then Tip Jar, then the general rows in order")
    func listFootFree() async {
        let jar = await jarWithTips()
        let pro = ProStatus(store: ProStatusTests.FakeStore())
        let consent = AdConsent(platform: AdTests.FakePlatform(), defaults: defaults())
        await consent.homeAppeared(isPro: false)
        #expect(consent.canRequestAds)

        let edition = AppExtensions.appStore(tipJar: jar, pro: pro, consent: consent)
        let rows = ListFoot(present: { _ in }).rows(with: edition).map(\.id)
        #expect(rows == ["ad", "tipJar"] + AppExtensionsTests.generalRows)
    }

    @Test("No ad before consent, and no Tip Jar before the store has answered")
    func listFootBeforeAnswers() {
        let jar = TipJar(store: TipJarTests.FakeStore(tips: TipJarTests.three))
        let pro = ProStatus(store: ProStatusTests.FakeStore())
        let consent = AdConsent(platform: AdTests.FakePlatform(), defaults: defaults())
        let edition = AppExtensions.appStore(tipJar: jar, pro: pro, consent: consent)
        let rows = ListFoot(present: { _ in }).rows(with: edition).map(\.id)
        #expect(rows == AppExtensionsTests.generalRows)
    }

    @Test("Tip Jar asks the list to present its sheet")
    func tipJarPresents() async {
        let jar = await jarWithTips()
        let pro = ProStatus(store: ProStatusTests.FakeStore())
        let consent = AdConsent(platform: AdTests.FakePlatform(), defaults: defaults())
        let edition = AppExtensions.appStore(tipJar: jar, pro: pro, consent: consent)
        var presented: [String] = []
        let rows = edition.listFootRows { presented.append($0.id) }
        #expect(rows.map(\.id) == ["tipJar"])
        #expect(presented.isEmpty, "nothing until the row is tapped")
    }

    @Test("The rating prompt waits for a free reader's tracking answer")
    func review() async {
        let platform = AdTests.FakePlatform()
        let consent = AdConsent(platform: platform, defaults: defaults())
        let pro = ProStatus(store: ProStatusTests.FakeStore())
        let edition = AppExtensions.appStore(tipJar: TipJar(store: TipJarTests.FakeStore()), pro: pro, consent: consent)
        #expect(!edition.mayAskForReview())
        platform.tracking = false
        #expect(edition.mayAskForReview())
    }

    @Test("Help and About offers Ad Privacy Options only where UMP requires it")
    func aboutRows() async {
        let platform = AdTests.FakePlatform()
        let consent = AdConsent(platform: platform, defaults: defaults())
        let pro = ProStatus(store: ProStatusTests.FakeStore())
        let edition = AppExtensions.appStore(tipJar: TipJar(store: TipJarTests.FakeStore()), pro: pro, consent: consent)
        await edition.settingsAppeared()
        #expect(edition.aboutRows().isEmpty)
        platform.optionsRequired = true
        await edition.settingsAppeared()
        #expect(edition.aboutRows().map(\.id) == ["adPrivacyOptions"])
    }
}
