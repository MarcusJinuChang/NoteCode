//
//  TipJarTests.swift
//  NoteCodeTests
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import NoteCode

@Suite("Tip jar", .serialized, .tags(.pro))
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
        try await productsServed(TipJar.productIDs)
        return session
    }

    /// Waits for the test session to serve its products. In a full run, with
    /// other suites going at once, StoreKit answered the first request with
    /// none (iPad mini simulator, 17 Oct), though alone it never did. Each
    /// request has a deadline (`answered(_:within:_:)`), and a session that
    /// never serves them fails here rather than at an `#expect` further on.
    private func productsServed(_ ids: [String]) async throws {
        for _ in 0..<50 {
            let served = try await answered("the test session's products") {
                try await Product.products(for: ids).count
            }
            if served == ids.count { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw StoreKitTestFailure.productsNotServed(ids)
    }

    @Test("The jar asks for the products the configuration sells, and a tip is thanked and finished")
    func storeKitPurchase() async throws {
        let session = try await session()
        let jar = TipJar(store: StoreKitTipStore())
        try await answered("the jar's products") {
            jar.load()
            await jar.loaded()
        }
        #expect(jar.tips.map(\.id) == TipJar.productIDs)
        #expect(jar.tips.map(\.name) == ["Small Tip", "Medium Tip", "Large Tip"])

        let tip = try #require(jar.tips.last)
        try await answered("the purchase") { await jar.buy(tip) }
        #expect(jar.phase == .thanked)
        #expect(session.allTransactions().count == 1)

        // A consumable left unfinished is delivered again at every launch.
        let unfinished = try await answered("the unfinished transactions") {
            var count = 0
            for await _ in Transaction.unfinished { count += 1 }
            return count
        }
        #expect(unfinished == 0)
        session.clearTransactions()
    }

    @Test("With Ask to Buy on, a tip waits for approval")
    func storeKitAskToBuy() async throws {
        let session = try await session()
        session.askToBuyEnabled = true
        let jar = TipJar(store: StoreKitTipStore())
        try await answered("the jar's products") {
            jar.load()
            await jar.loaded()
        }

        let tip = try #require(jar.tips.first)
        try await answered("the purchase") { await jar.buy(tip) }
        #expect(jar.phase == .pending)
        session.clearTransactions()
    }

    @Test("A StoreKit call that never answers fails at its deadline, not at the run's allowance")
    func deadline() async throws {
        // Stands in for StoreKit stuck behind a sign-in alert: it ignores
        // cancellation and answers only when told to.
        let gate = Gate()
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: StoreKitTestFailure.noAnswer("a call that never answers", seconds: 1)) {
            try await answered("a call that never answers", within: 1) {
                await gate.wait()
            }
        }
        #expect(clock.now - start < .seconds(10))
        gate.open()

        // An answer in time is passed through.
        #expect(try await answered("an answer") { 7 } == 7)
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
        try await productsServed([ProStatus.productID])
        return session
    }

    @Test("The configuration sells the monthly product at $4.99, which buys, finishes, restores, and a refund ends it")
    func storeKitPurchaseAndRestore() async throws {
        let session = try await proSession()
        let pro = ProStatus(store: StoreKitProStore())
        try await answered("the product") { await pro.loadedProduct() }
        #expect(pro.product?.name == "NoteCode Pro")
        #expect(pro.product?.price == "$4.99")

        try await answered("the purchase") { await pro.buy() }
        #expect(pro.isPro)
        #expect(pro.expirationDate != nil)
        #expect(pro.signedTransaction?.split(separator: ".").count == 3)

        // Not asserted: that `finish()` took. The test session listed a bought
        // subscription as unfinished after it, run to run (simulator, 27 Oct),
        // which a tip does not do.

        // A fresh model, as after a relaunch or on another iPad.
        let again = ProStatus(store: StoreKitProStore())
        try await answered("the restore") { await again.restore() }
        #expect(again.isPro)

        // A refund ends it.
        let transaction = try #require(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.identifier))
        // The test session pushed no `Transaction.updates` for a refund (simulator,
        // 27 Oct), so this is the launch path: a refunded transaction is no
        // longer among the current entitlements. The live path is `revocation`.
        for _ in 0..<40 where pro.isPro {
            try await answered("the entitlements") { await pro.refresh() }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!pro.isPro)

        // The refund is a transaction nobody finished here, which the tip jar's
        // test would count as left over.
        try await answered("finishing the refund") {
            for await case .verified(let revoked) in Transaction.unfinished { await revoked.finish() }
        }
        session.clearTransactions()
    }
}

// MARK: - A deadline for each StoreKit call

// D10 (docs/refactor/debt.md). The purchase test waited 11.5 hours once and
// ran out the run's 120 s allowance in most full runs of 6 to 8 Nov. The
// spindump xcodebuild took at the allowance (6 Nov) shows the app idle,
// waiting on storekitd; storekitd waiting on appstored, the real App Store's
// daemon rather than the test session; and appstored inside AuthKit's
// `presentBasicLoginUIWithCompletion`. A screenshot of the hang (8 Nov) is a
// "Sign in to Apple Account" alert over the app, which nobody answers.
//
// It happens on a simulator that has never run a StoreKit test session: on
// one just made or erased, the first test process's purchases go to the App
// Store, every one of them, whenever the session was made and with the app's
// own launch requests taken out. Every later process on that simulator,
// including after a reboot, buys from the session in under half a second.
// The overnight runs each made a fresh simulator, hence "most runs".
//
// StoreKit's calls take no timeout and ignore cancellation, so each call
// here has a deadline. One that passes fails the test, naming the step,
// without waiting for the call, which is left behind as it would be anyway.

/// Why a StoreKit test stopped.
private nonisolated enum StoreKitTestFailure: Error, Equatable, CustomStringConvertible {
    case noAnswer(String, seconds: Int)
    case productsNotServed([String])

    var description: String {
        switch self {
        case let .noAnswer(step, seconds):
            "StoreKit gave no answer for \(step) within \(seconds) s. On a simulator that has never run a "
                + "StoreKit test session, the first test process's purchases go to the App Store, which "
                + "waits on an Apple ID sign-in alert; run again on the same simulator (docs/refactor/debt.md, D10)."
        case let .productsNotServed(ids):
            "The StoreKit test session served none or only some of \(ids) in 5 s."
        }
    }
}

/// Runs `body` on the main actor and returns its answer, or throws
/// `StoreKitTestFailure.noAnswer` once `seconds` pass, without waiting for
/// `body` to finish. The deadline is a timer, not a sleep: an answer in
/// time returns at once.
@MainActor
private func answered<T: Sendable>(_ step: String, within seconds: Int = 20,
                           _ body: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let first = FirstAnswer(continuation)
        let work = Task { @MainActor in
            do { first.resume(with: .success(try await body())) } catch { first.resume(with: .failure(error)) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds)) {
            work.cancel()
            first.resume(with: .failure(StoreKitTestFailure.noAnswer(step, seconds: seconds)))
        }
    }
}

/// Resumes a continuation once, with whichever answer comes first.
private nonisolated final class FirstAnswer<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, any Error>) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(with: result)
    }
}

/// A wait that ignores cancellation and ends only when opened, as a StoreKit
/// request behind an alert does.
private nonisolated final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        opened = true
        let all = waiting
        waiting = []
        lock.unlock()
        all.forEach { $0.resume() }
    }
}
