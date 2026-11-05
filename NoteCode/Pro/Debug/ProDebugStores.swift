//
//  ProDebugStores.swift
//  NoteCode
//
//  What the App Store edition's debug launch options put in place of
//  StoreKit and the run service, and the debug paywall. Debug builds only.
//

import SwiftUI

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

#if DEBUG
nonisolated enum DebugRunStubKind: String, CaseIterable, Sendable {
    case ok, compileError = "compile-error", runtimeError = "runtime-error"
    case timeLimit = "time-limit", capped
}

/// Canned answers for `-debug-run-stub`, so the panel can be seen without a proxy.
nonisolated struct DebugRunStub: CodeRunning {
    var kind: DebugRunStubKind

    func run(_ job: RunJob) async throws -> RunResult {
        try await Task.sleep(for: .milliseconds(400))
        switch kind {
        case .ok:
            return RunResult(status: .ok, stdout: "Hello, NoteCode\n42\n", timeSeconds: 0.02, memoryKB: 3174, runsLeft: 18)
        case .compileError:
            return RunResult(
                status: .compileError,
                compileOutput: "main.cpp:5:3: error: use of undeclared identifier 'cout'\n  cout << x;\n  ^\n",
                runsLeft: 17
            )
        case .runtimeError:
            return RunResult(
                status: .runtimeError(exitCode: 1, signal: nil), stdout: "before\n",
                stderr: "terminate called after throwing an instance of 'std::out_of_range'\n",
                timeSeconds: 0.01, memoryKB: 2900
            )
        case .timeLimit:
            return RunResult(status: .timeLimit, stdout: "1\n2\n3\n", timeSeconds: 5.0, memoryKB: 2048)
        case .capped:
            throw RunServiceError.capped(RunCap(scope: .daily, runsLeft: 0, resetsAt: nil))
        }
    }
}
#endif

#if DEBUG
/// `-debug-paywall`: the paywall over whatever opens, for a screenshot.
struct DebugPaywall: ViewModifier {
    @State private var shows = ProDebugOptions.current.paywall

    func body(content: Content) -> some View {
        content.sheet(isPresented: $shows) {
            PaywallView(reason: "Explain Code and Summarise Note are part of NoteCode Pro.")
                .environment(ProStatus.shared)
                .modifier(AppearanceModifier())
        }
    }
}
#endif
