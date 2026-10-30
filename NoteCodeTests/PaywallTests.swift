//
//  PaywallTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Paywall and the AI gate", .serialized)
@MainActor
struct PaywallTests {

    private func job() -> AIJob {
        AIPrompts.explainJob(code: "int add(int a, int b) { return a + b; }", languageName: "C++",
                             insertionOffset: 0, contextTokens: 4096, length: .brief)
    }

    private func status(pro: Bool) async -> ProStatus {
        let held = pro ? ProStatusTests.entitlement() : nil
        let status = ProStatus(store: ProStatusTests.FakeStore(held: held), now: { ProStatusTests.now })
        status.start()
        await status.started()
        return status
    }

    @Test("A free reader's AI action opens the paywall and starts no model session")
    func freeIsGated() async {
        let model = FakeTextModel()
        let pro = await status(pro: false)
        let ai = AIAssistant(client: model, isPro: { pro.isPro })

        ai.begin(job())

        #expect(ai.needsPro)
        #expect(ai.job == nil, "the result sheet doesn't open")
        #expect(ai.state == .idle)
        #expect(model.requests.isEmpty, "the model is never asked")
    }

    @Test("A Pro reader's AI action runs as it did")
    func proRuns() async {
        let model = FakeTextModel()
        let pro = await status(pro: true)
        let ai = AIAssistant(client: model, isPro: { pro.isPro })

        ai.begin(job())
        for _ in 0..<200 {
            if case .done = ai.state { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(!ai.needsPro)
        #expect(ai.job != nil)
        #expect(model.requests.count == 1)
        if case .done = ai.state {} else { Issue.record("expected done, got \(ai.state)") }
    }

    @Test("Buying Pro lifts the gate without a relaunch")
    func gateFollowsStatus() async {
        let store = ProStatusTests.FakeStore()
        store.outcome = .purchased(ProStatusTests.entitlement())
        let pro = ProStatus(store: store, now: { ProStatusTests.now })
        let ai = AIAssistant(client: FakeTextModel(), isPro: { pro.isPro })

        ai.begin(job())
        #expect(ai.needsPro)
        ai.needsPro = false

        await pro.buy()
        ai.begin(job())
        #expect(!ai.needsPro)
        ai.dismiss()
    }

    @Test("The paywall's strings: price, period, Restore, Terms, Privacy, and the three gifts")
    func strings() {
        let product = ProProduct(id: ProStatus.productID, name: "NoteCode Pro", price: "$4.99")
        #expect(PaywallContent.priceLine(product) == "$4.99 per month")
        #expect(PaywallContent.restore == "Restore Purchases")
        #expect(PaywallContent.termsTitle == "Terms of Use")
        #expect(PaywallContent.privacyTitle == "Privacy Policy")
        #expect(PaywallContent.terms.host == "www.apple.com")
        #expect(PaywallContent.renewal.contains("cancel"))
        #expect(PaywallContent.renewal.contains("at least 24 hours before the end of the current period"),
                "Apple's cancellation wording (QC S4)")
        #expect(PaywallContent.retry == "Try Again")
        #expect(PaywallContent.features.map(\.id) == ["ads", "run", "ai"])
        #expect(PaywallContent.priceLine(nil) != "$4.99 per month")
    }

    @Test("It says whether this iPad can use the AI, and that the rest works anyway")
    func availability() {
        #expect(PaywallContent.aiAvailability(.available).contains("ready"))
        let ineligible = PaywallContent.aiAvailability(.unavailable(.deviceNotEligible))
        #expect(ineligible.contains(AIUnavailableReason.deviceNotEligible.message))
        #expect(ineligible.contains("Run and no ads"))
    }
}
