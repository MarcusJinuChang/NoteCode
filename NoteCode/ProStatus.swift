//
//  ProStatus.swift
//  NoteCode
//
//  Whether the reader has Pro: one auto-renewable subscription.
//

import Foundation
import Observation
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// The subscription as the store describes it.
struct ProProduct: Equatable, Sendable {
    let id: String
    let name: String
    /// The price as the store shows it, in the reader's currency.
    let price: String
}

/// A transaction that grants Pro, as far as the app needs to know it.
struct ProEntitlement: Equatable, Sendable {
    let productID: String
    /// When the current period ends.
    let expirationDate: Date?
    /// Set when the App Store refunded or revoked the purchase.
    let revocationDate: Date?
    /// The signed transaction (JWS) as StoreKit delivered it. R4 sends this
    /// to the Run proxy, which verifies Apple's signature itself.
    let signedTransaction: String
}

/// How a purchase came out.
enum ProPurchaseOutcome: Equatable, Sendable {
    case purchased(ProEntitlement)
    case cancelled
    /// Waiting for someone else, Ask to Buy. It arrives later, if at all,
    /// through `ProStore.updates`.
    case pending
}

/// What `ProStatus` needs from a store: StoreKit in the app, a fake in tests
/// and a fixed answer under `-debug-pro`.
protocol ProStore: Sendable {
    func product(id: String) async throws -> ProProduct?
    /// The entitlement the store holds now, if any.
    func currentEntitlement(for id: String) async -> ProEntitlement?
    func purchase(id: String) async throws -> ProPurchaseOutcome
    /// Asks the store to fetch the reader's purchases again (Restore).
    func sync() async throws
    /// Transactions for the product that arrive outside a purchase: a
    /// renewal, an Ask to Buy approval, a refund. Already finished.
    func updates(for id: String) -> AsyncStream<ProEntitlement>
}

/// Whether the reader has Pro. **The one thing Run, AI and ads read.**
///
/// Fed by `Transaction.currentEntitlements` at launch and `Transaction.updates`
/// while running; a revoked or expired transaction ends Pro. Kept apart from
/// `TipJar`, which records nothing: tips unlock nothing, Pro is state.
@Observable
@MainActor
final class ProStatus {
    /// The product in App Store Connect and in `NoteCode.storekit`.
    nonisolated static let productID = "com.marcus.NoteCode.pro.monthly"

    enum Phase: Equatable {
        case ready
        case buying
        case restoring
        case pending
        case failed(String)
    }

    /// The one the app uses. Tests make their own.
    static let shared: ProStatus = {
#if DEBUG
        if let pro = DebugLaunchOptions.current.pro { return ProStatus(store: DebugProStore(grants: pro)) }
#endif
        return ProStatus(store: StoreKitProStore())
    }()

    private(set) var entitlement: ProEntitlement?
    private(set) var product: ProProduct?
    /// The last ask for the product failed or found none (offline, or the
    /// product not attached to the build), so the paywall offers Try Again
    /// rather than "Loading the price…" for ever.
    private(set) var productFailed = false
    private(set) var phase: Phase = .ready

    /// Whether Pro is on: an entitlement that isn't revoked or past its end.
    var isPro: Bool {
        guard let entitlement, entitlement.revocationDate == nil else { return false }
        return entitlement.expirationDate.map { $0 > now() } ?? true
    }

    /// When the current period ends, while the reader has Pro.
    var expirationDate: Date? { isPro ? entitlement?.expirationDate : nil }

    /// The signed transaction R4 sends to the proxy; nil for a free reader.
    var signedTransaction: String? { isPro ? entitlement?.signedTransaction : nil }

    private let store: any ProStore
    private let now: @Sendable () -> Date
    private var updates: Task<Void, Never>?
    private var loading: Task<Void, Never>?

    init(store: any ProStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    /// Listens for transactions from launch, reads the entitlement the store
    /// holds and asks for the product. StoreKit expects the listener from
    /// launch, or a renewal or approval that arrived while the app was closed
    /// is redelivered at every launch.
    func start() {
        if updates == nil {
            let stream = store.updates(for: Self.productID)
            updates = Task { [weak self] in
                for await update in stream { self?.apply(update) }
            }
        }
        loading = Task { await refresh() }
        loadProduct()
    }

    /// Waits for what `start` began. For tests.
    func started() async {
        await loading?.value
    }

    /// Reads the entitlement the store holds now.
    func refresh() async {
        entitlement = await store.currentEntitlement(for: Self.productID)
    }

    /// Asks the store for the product, unless it has it. A failed answer can
    /// be asked again.
    func loadProduct() {
        guard product == nil else { return }
        productFailed = false
        Task { await loadedProduct() }
    }

    /// Asks for the product and waits for the answer. `loadProduct` doesn't
    /// wait; tests do.
    func loadedProduct() async {
        product = try? await store.product(id: Self.productID)
        productFailed = product == nil
    }

    /// Takes in a transaction that arrived on its own. A revoked one ends Pro.
    func apply(_ update: ProEntitlement) {
        guard update.productID == Self.productID else { return }
        entitlement = update.revocationDate == nil ? update : nil
    }

    func buy() async {
        guard phase != .buying else { return }
        phase = .buying
        do {
            switch try await store.purchase(id: Self.productID) {
            case .purchased(let bought): apply(bought); phase = .ready
            case .cancelled:             phase = .ready
            case .pending:               phase = .pending
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Restore: asks the App Store for the reader's purchases (this may ask
    /// for their Apple Account), then reads what it holds.
    func restore() async {
        guard phase != .restoring else { return }
        phase = .restoring
        do {
            try await store.sync()
            await refresh()
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Back to ready, when the paywall is opened again.
    func reset() {
        phase = .ready
    }

#if canImport(UIKit) && !os(visionOS)
    /// Opens the system's subscription management.
    func manage() async {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }
#endif
}

/// The App Store, through StoreKit 2.
struct StoreKitProStore: ProStore {
    func product(id: String) async throws -> ProProduct? {
        try await Product.products(for: [id]).first.map {
            ProProduct(id: $0.id, name: $0.displayName, price: $0.displayPrice)
        }
    }

    func currentEntitlement(for id: String) async -> ProEntitlement? {
        var best: ProEntitlement?
        for await result in Transaction.currentEntitlements {
            guard let held = Self.entitlement(result, for: id), held.revocationDate == nil else { continue }
            if best == nil || (held.expirationDate ?? .distantFuture) > (best?.expirationDate ?? .distantFuture) {
                best = held
            }
        }
        return best
    }

    func purchase(id: String) async throws -> ProPurchaseOutcome {
        guard let product = try await Product.products(for: [id]).first else { throw ProFailure.notFound }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result, let held = Self.entitlement(result, for: id) else {
                throw ProFailure.unverified
            }
            await transaction.finish()
            return .purchased(held)
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    func sync() async throws {
        try await AppStore.sync()
    }

    func updates(for id: String) -> AsyncStream<ProEntitlement> {
        AsyncStream { continuation in
            let task = Task.detached {
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result, let held = Self.entitlement(result, for: id) else { continue }
                    await transaction.finish()
                    continuation.yield(held)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The entitlement a verified transaction for `id` stands for.
    private static func entitlement(_ result: VerificationResult<Transaction>, for id: String) -> ProEntitlement? {
        guard case .verified(let transaction) = result, transaction.productID == id else { return nil }
        return ProEntitlement(
            productID: transaction.productID,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            signedTransaction: result.jwsRepresentation
        )
    }
}

enum ProFailure: LocalizedError {
    case notFound
    case unverified

    var errorDescription: String? {
        switch self {
        case .notFound:   "NoteCode Pro isn't available right now."
        case .unverified: "The App Store couldn't confirm the purchase, so nothing was charged."
        }
    }
}

#if DEBUG
/// `-debug-pro on|off`: Pro granted or not, with nothing asked of StoreKit.
/// Buying grants it, so the paywall can be walked through either way.
struct DebugProStore: ProStore {
    let grants: Bool

    private var granted: ProEntitlement {
        ProEntitlement(productID: ProStatus.productID, expirationDate: Date().addingTimeInterval(30 * 86_400),
                       revocationDate: nil, signedTransaction: "debug.jws.signature")
    }

    func product(id: String) async throws -> ProProduct? {
        ProProduct(id: id, name: "NoteCode Pro", price: "$4.99")
    }

    func currentEntitlement(for id: String) async -> ProEntitlement? { grants ? granted : nil }

    func purchase(id: String) async throws -> ProPurchaseOutcome {
        try await Task.sleep(for: .milliseconds(600))
        return .purchased(granted)
    }

    func sync() async throws {}

    func updates(for id: String) -> AsyncStream<ProEntitlement> { AsyncStream { $0.finish() } }
}
#endif
