//
//  ProStatusTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Pro status", .serialized)
@MainActor
struct ProStatusTests {

    /// A store that answers what it's told to, and can push updates.
    final class FakeStore: ProStore, @unchecked Sendable {
        var held: ProEntitlement?
        var outcome: ProPurchaseOutcome = .cancelled
        var fails = false
        private var continuation: AsyncStream<ProEntitlement>.Continuation?

        struct Failed: LocalizedError {
            var errorDescription: String? { "The store said no." }
        }

        init(held: ProEntitlement? = nil) { self.held = held }

        func product(id: String) async throws -> ProProduct? {
            ProProduct(id: id, name: "NoteCode Pro", price: "$4.99")
        }
        func currentEntitlement(for id: String) async -> ProEntitlement? { held }
        func purchase(id: String) async throws -> ProPurchaseOutcome {
            if fails { throw Failed() }
            return outcome
        }
        func sync() async throws { if fails { throw Failed() } }
        func updates(for id: String) -> AsyncStream<ProEntitlement> {
            AsyncStream { continuation = $0 }
        }
        func push(_ update: ProEntitlement) { continuation?.yield(update) }
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func entitlement(expires: TimeInterval? = 86_400, revoked: Bool = false,
                            id: String = ProStatus.productID) -> ProEntitlement {
        ProEntitlement(productID: id,
                       expirationDate: expires.map { now.addingTimeInterval($0) },
                       revocationDate: revoked ? now : nil,
                       signedTransaction: "header.payload.signature")
    }

    private func status(_ store: FakeStore) -> ProStatus {
        ProStatus(store: store, now: { Self.now })
    }

    @Test("Free until the store holds an entitlement; Pro once it does")
    func onAndOff() async {
        let free = status(FakeStore())
        free.start()
        await free.started()
        #expect(!free.isPro)
        #expect(free.signedTransaction == nil)

        let pro = status(FakeStore(held: Self.entitlement()))
        #expect(!pro.isPro, "nothing is known before the store has answered")
        pro.start()
        await pro.started()
        #expect(pro.isPro)
    }

    @Test("Pro ends at the expiry, and exposes it only while it lasts")
    func expiry() async {
        let store = FakeStore(held: Self.entitlement(expires: 3_600))
        let pro = status(store)
        pro.start()
        await pro.started()
        #expect(pro.expirationDate == Self.now.addingTimeInterval(3_600))

        let lapsed = status(FakeStore(held: Self.entitlement(expires: -1)))
        lapsed.start()
        await lapsed.started()
        #expect(!lapsed.isPro)
        #expect(lapsed.expirationDate == nil)
        #expect(lapsed.signedTransaction == nil)
    }

    @Test("A revoked or refunded transaction ends Pro, an unrelated one doesn't")
    func revocation() async {
        let store = FakeStore(held: Self.entitlement())
        let pro = status(store)
        pro.start()
        await pro.started()
        #expect(pro.isPro)

        pro.apply(Self.entitlement(revoked: true, id: "com.marcus.NoteCode.tip.small"))
        #expect(pro.isPro)

        pro.apply(Self.entitlement(revoked: true))
        #expect(!pro.isPro)
        #expect(pro.signedTransaction == nil)
    }

    @Test("A renewal arriving while running keeps Pro going, a refund ends it")
    func updatesWhileRunning() async throws {
        let store = FakeStore()
        let pro = status(store)
        pro.start()
        await pro.started()
        #expect(!pro.isPro)

        store.push(Self.entitlement())
        try await waitFor { pro.isPro }

        store.push(Self.entitlement(revoked: true))
        try await waitFor { !pro.isPro }
    }

    @Test("The signed transaction is exposed for the proxy, and only to a Pro reader")
    func signedTransaction() async {
        let pro = status(FakeStore(held: Self.entitlement()))
        pro.start()
        await pro.started()
        #expect(pro.signedTransaction == "header.payload.signature")
    }

    @Test("A purchase turns Pro on; cancelled, pending and failed don't")
    func purchases() async {
        let store = FakeStore()
        let pro = status(store)

        store.outcome = .purchased(Self.entitlement())
        await pro.buy()
        #expect(pro.isPro)
        #expect(pro.phase == .ready)

        let other = status(FakeStore())
        await other.buy()
        #expect(!other.isPro)
        #expect(other.phase == .ready)

        let waiting = FakeStore(); waiting.outcome = .pending
        let pending = status(waiting)
        await pending.buy()
        #expect(!pending.isPro)
        #expect(pending.phase == .pending)

        let broken = FakeStore(); broken.fails = true
        let failed = status(broken)
        await failed.buy()
        #expect(failed.phase == .failed("The store said no."))
    }

    @Test("Restore reads what the store holds now")
    func restore() async {
        let store = FakeStore()
        let pro = status(store)
        await pro.restore()
        #expect(!pro.isPro)

        store.held = Self.entitlement()
        await pro.restore()
        #expect(pro.isPro)

        store.fails = true
        await pro.restore()
        #expect(pro.phase == .failed("The store said no."))
    }

    @Test("The product is loaded for the paywall's price")
    func product() async {
        let pro = status(FakeStore())
        await pro.loadedProduct()
        #expect(pro.product?.price == "$4.99")
    }

    @Test("-debug-pro on and off, and a bad value")
    func debugLaunch() {
        #expect(DebugLaunchOptions.parse(["app", "-debug-pro", "on"]).pro == true)
        #expect(DebugLaunchOptions.parse(["app", "-debug-pro", "off"]).pro == false)
        #expect(DebugLaunchOptions.parse(["app"]).pro == nil)
        let bad = DebugLaunchOptions.parse(["app", "-debug-pro", "maybe"])
        #expect(bad.pro == nil)
        #expect(!bad.problems.isEmpty)
    }

    @Test("The debug stand-in grants Pro or not, and a purchase grants it")
    func debugStore() async {
        let on = ProStatus(store: DebugProStore(grants: true))
        on.start()
        await on.started()
        #expect(on.isPro)

        let off = ProStatus(store: DebugProStore(grants: false))
        off.start()
        await off.started()
        #expect(!off.isPro)
        await off.buy()
        #expect(off.isPro)
    }

    func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
        #expect(condition())
    }
}
