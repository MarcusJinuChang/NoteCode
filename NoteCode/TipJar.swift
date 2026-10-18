//
//  TipJar.swift
//  NoteCode
//
//  Tips through In-App Purchase: three consumables that unlock nothing.
//

import Foundation
import Observation
import StoreKit

/// One tip the reader can leave, as the store describes it.
struct Tip: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// The price as the store shows it, in the reader's currency.
    let price: String
    /// For ordering, smallest first.
    let amount: Decimal
}

/// How a purchase came out.
enum TipOutcome: Equatable, Sendable {
    case thanked
    case cancelled
    /// Waiting for someone else, Ask to Buy. The tip arrives later, if at all,
    /// through `Transaction.updates`.
    case pending
}

/// What the tip jar needs from a store. StoreKit in the app; a fake in tests
/// of the jar's states, so they don't depend on a store being set up.
protocol TipStore: Sendable {
    func tips(for ids: [String]) async throws -> [Tip]
    func purchase(_ id: String) async throws -> TipOutcome
}

/// The tip jar, decided 17 Oct (step 2 of docs/ROADMAP.md): tips go through
/// In-App Purchase rather than a link to a tipping site, which guideline 3.1.1
/// still routes through In-App Purchase and App Review has rejected in an
/// About page. A tip is a consumable that unlocks nothing, so there is
/// nothing to restore and nothing to keep: the jar records no purchase.
///
/// The row that opens it shows only once the store has answered with the
/// products (`isAvailable`), as Send Feedback shows only once there is an
/// address. Until the products exist in App Store Connect, and the Paid
/// Applications agreement is signed, there is no row.
@Observable
@MainActor
final class TipJar {
    /// The products, as set up in App Store Connect and in `NoteCode.storekit`.
    nonisolated static let productIDs = [
        "com.marcus.NoteCode.tip.small",
        "com.marcus.NoteCode.tip.medium",
        "com.marcus.NoteCode.tip.large",
    ]

    enum Phase: Equatable {
        case ready
        case buying(Tip.ID)
        case thanked
        case pending
        case failed(String)
    }

    /// The one the app uses. Tests make their own.
    static let shared: TipJar = {
#if DEBUG
        if DebugLaunchOptions.current.tipJar { return TipJar(store: DebugTipStore()) }
#endif
        return TipJar(store: StoreKitTipStore())
    }()

    private(set) var tips: [Tip] = []
    private(set) var phase: Phase = .ready
    var isAvailable: Bool { !tips.isEmpty }

    private let store: any TipStore
    private var loading: Task<Void, Never>?
    private var updates: Task<Void, Never>?

    init(store: any TipStore) {
        self.store = store
    }

    /// Asks the store for the tips, once, and starts finishing transactions
    /// that arrive outside a purchase (Ask to Buy approved later, a purchase
    /// interrupted by the app closing). StoreKit expects that listener from
    /// launch, or such a tip is redelivered at every launch, never finished.
    func start() {
        if updates == nil, store is StoreKitTipStore {
            updates = Task.detached {
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update {
                        await transaction.finish()
                    }
                }
            }
        }
        load()
    }

    /// Asks the store for the tips, unless it is already answering. A failed
    /// answer leaves the jar unavailable and can be asked again later.
    func load() {
        guard loading == nil, tips.isEmpty else { return }
        loading = Task {
            let found = (try? await store.tips(for: Self.productIDs)) ?? []
            tips = found.sorted { $0.amount < $1.amount }
            loading = nil
        }
    }

    /// Waits for a load in flight. For tests.
    func loaded() async {
        await loading?.value
    }

    func buy(_ tip: Tip) async {
        guard phase != .buying(tip.id) else { return }
        phase = .buying(tip.id)
        do {
            switch try await store.purchase(tip.id) {
            case .thanked:   phase = .thanked
            case .cancelled: phase = .ready
            case .pending:   phase = .pending
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Back to the tips, when the sheet is opened again.
    func reset() {
        phase = .ready
    }
}

/// The App Store, through StoreKit 2.
struct StoreKitTipStore: TipStore {
    enum Failure: LocalizedError {
        case notFound
        case unverified

        var errorDescription: String? {
            switch self {
            case .notFound:   "That tip isn't available right now."
            case .unverified: "The App Store couldn't confirm the purchase, so nothing was charged."
            }
        }
    }

    func tips(for ids: [String]) async throws -> [Tip] {
        try await Product.products(for: ids).map {
            Tip(id: $0.id, name: $0.displayName, price: $0.displayPrice, amount: $0.price)
        }
    }

    func purchase(_ id: String) async throws -> TipOutcome {
        guard let product = try await Product.products(for: [id]).first else { throw Failure.notFound }
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            // A consumable is finished as soon as it's delivered, and a tip
            // delivers nothing.
            await transaction.finish()
            return .thanked
        case .success(.unverified):
            throw Failure.unverified
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }
}

#if DEBUG
/// `-debug-tip-jar`: three tips at made-up prices, each thanked after a
/// moment, with nothing charged and nothing asked of StoreKit.
struct DebugTipStore: TipStore {
    func tips(for ids: [String]) async throws -> [Tip] {
        zip(ids, [("Small Tip", "$0.99", 0.99), ("Medium Tip", "$2.99", 2.99), ("Large Tip", "$4.99", 4.99)])
            .map { Tip(id: $0, name: $1.0, price: $1.1, amount: Decimal($1.2)) }
    }

    func purchase(_ id: String) async throws -> TipOutcome {
        try await Task.sleep(for: .milliseconds(600))
        return .thanked
    }
}
#endif
