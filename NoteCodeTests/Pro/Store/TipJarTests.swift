//
//  TipJarTests.swift
//  NoteCodeTests
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import NoteCode

@Suite("Tip jar", .serialized)
@MainActor
struct TipJarTests {

    /// A store that answers what it's told to.
    struct FakeStore: TipStore {
        var tips: [Tip] = []
        var outcome: TipOutcome = .thanked
        var fails = false

        struct Failed: LocalizedError {
            var errorDescription: String? { "The store said no." }
        }

        func tips(for ids: [String]) async throws -> [Tip] {
            if fails { throw Failed() }
            return tips
        }

        func purchase(_ id: String) async throws -> TipOutcome {
            if fails { throw Failed() }
            return outcome
        }
    }

    static let three = [
        Tip(id: "large", name: "Large Tip", price: "$4.99", amount: 4.99),
        Tip(id: "small", name: "Small Tip", price: "$0.99", amount: 0.99),
        Tip(id: "medium", name: "Medium Tip", price: "$2.99", amount: 2.99),
    ]

    @Test("The jar is offered only once the store has answered with tips, smallest first")
    func availableOnceLoaded() async {
        let jar = TipJar(store: FakeStore(tips: Self.three))
        #expect(!jar.isAvailable)
        jar.load()
        await jar.loaded()
        #expect(jar.isAvailable)
        #expect(jar.tips.map(\.id) == ["small", "medium", "large"])

        let empty = TipJar(store: FakeStore())
        empty.load()
        await empty.loaded()
        #expect(!empty.isAvailable)

        let failing = TipJar(store: FakeStore(tips: Self.three, fails: true))
        failing.load()
        await failing.loaded()
        #expect(!failing.isAvailable)
    }

    @Test("A purchase ends thanked, back at the tips, waiting, or with the store's reason",
          arguments: [TipOutcome.thanked, .cancelled, .pending])
    func outcomes(_ outcome: TipOutcome) async {
        let jar = TipJar(store: FakeStore(tips: Self.three, outcome: outcome))
        jar.load()
        await jar.loaded()
        await jar.buy(jar.tips[0])
        switch outcome {
        case .thanked:   #expect(jar.phase == .thanked)
        case .cancelled: #expect(jar.phase == .ready)
        case .pending:   #expect(jar.phase == .pending)
        }

        jar.reset()
        #expect(jar.phase == .ready)
    }

    @Test("A failed purchase says why")
    func failure() async {
        let jar = TipJar(store: FakeStore(tips: Self.three, fails: true))
        await jar.buy(Self.three[0])
        #expect(jar.phase == .failed("The store said no."))
    }

    // MARK: - Through StoreKit, against NoteCode.storekit

    // The configuration is in the test bundle, beside these tests: StoreKit's
    // test session read nothing from a file outside it (simulator, 17 Oct).

    private func session() async throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "NoteCode")
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
        try await productsServed()
        return session
    }

    /// Waits for the test session to serve its products. In a full run, with
    /// other suites going at once, StoreKit answered the first request with
    /// none (iPad mini simulator, 17 Oct), though alone it never did.
    private func productsServed() async throws {
        for _ in 0..<50 {
            if try await Product.products(for: TipJar.productIDs).count == TipJar.productIDs.count { return }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test("The jar asks for the products the configuration sells, and a tip is thanked and finished")
    func storeKitPurchase() async throws {
        let session = try await session()
        let jar = TipJar(store: StoreKitTipStore())
        jar.load()
        await jar.loaded()
        #expect(jar.tips.map(\.id) == TipJar.productIDs)
        #expect(jar.tips.map(\.name) == ["Small Tip", "Medium Tip", "Large Tip"])

        await jar.buy(try #require(jar.tips.last))
        #expect(jar.phase == .thanked)
        #expect(session.allTransactions().count == 1)

        // A consumable left unfinished is delivered again at every launch.
        var unfinished = 0
        for await _ in Transaction.unfinished { unfinished += 1 }
        #expect(unfinished == 0)
        session.clearTransactions()
    }

    @Test("With Ask to Buy on, a tip waits for approval")
    func storeKitAskToBuy() async throws {
        let session = try await session()
        session.askToBuyEnabled = true
        let jar = TipJar(store: StoreKitTipStore())
        jar.load()
        await jar.loaded()

        await jar.buy(try #require(jar.tips.first))
        #expect(jar.phase == .pending)
        session.clearTransactions()
    }

    @Test("The mail rows wait for an address, under their own subjects")
    func mailRows() {
        #expect(AppInfo.featureRequestURL(address: nil) == nil)
        #expect(AppInfo.featureRequestURL(address: "") == nil)
        let request = AppInfo.featureRequestURL(address: "hello@example.com")
        let feedback = AppInfo.feedbackURL(address: "hello@example.com")
        #expect(request?.scheme == "mailto")
        #expect(request?.absoluteString.contains("Feature%20Request") == true)
        #expect(feedback?.absoluteString.contains("Feedback") == true)
        #expect(request != feedback)
    }
}

// Through StoreKit, against NoteCode.storekit. These live in the tip jar's suite
// so they run one at a time with its tests: both buy from the one StoreKit test
// session, and run side by side a purchase from one was seen unfinished by the
// other (simulator, 27 Oct).
extension TipJarTests {

    private func proSession() async throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "NoteCode")
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
        for _ in 0..<50 {
            if try await Product.products(for: [ProStatus.productID]).count == 1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        return session
    }

    @Test("The configuration sells the monthly product at $4.99, which buys, finishes, restores, and a refund ends it")
    func storeKitPurchaseAndRestore() async throws {
        let session = try await proSession()
        let pro = ProStatus(store: StoreKitProStore())
        await pro.loadedProduct()
        #expect(pro.product?.name == "NoteCode Pro")
        #expect(pro.product?.price == "$4.99")

        await pro.buy()
        #expect(pro.isPro)
        #expect(pro.expirationDate != nil)
        #expect(pro.signedTransaction?.split(separator: ".").count == 3)

        // Not asserted: that `finish()` took. The test session listed a bought
        // subscription as unfinished after it, run to run (simulator, 27 Oct),
        // which a tip does not do.

        // A fresh model, as after a relaunch or on another iPad.
        let again = ProStatus(store: StoreKitProStore())
        await again.restore()
        #expect(again.isPro)

        // A refund ends it.
        let transaction = try #require(session.allTransactions().first)
        try await session.refundTransaction(identifier: UInt(transaction.identifier))
        // The test session pushed no `Transaction.updates` for a refund (simulator,
        // 27 Oct), so this is the launch path: a refunded transaction is no
        // longer among the current entitlements. The live path is `revocation`.
        for _ in 0..<40 where pro.isPro {
            await pro.refresh()
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!pro.isPro)

        // The refund is a transaction nobody finished here, which the tip jar's
        // test would count as left over.
        for await case .verified(let revoked) in Transaction.unfinished { await revoked.finish() }
        session.clearTransactions()
    }
}
