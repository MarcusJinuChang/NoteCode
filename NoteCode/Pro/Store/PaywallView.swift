//
//  PaywallView.swift
//  NoteCode
//
//  What Pro gives, what it costs, and how to buy, restore or leave. Opened by
//  a free reader's AI action, Settings › Pro and (P3, R3) "Remove ads" and Run.
//

import SwiftUI

/// The words on the paywall, apart from the view so a test can read them.
/// App Review's guideline 3.1.2 wants the price, the period, a way to restore,
/// the Terms of Use and the privacy policy on a subscription screen.
nonisolated enum PaywallContent {
    static let title = "NoteCode Pro"
    static let period = "per month"
    static let renewal = "Renews every month until you cancel it in your Apple Account's subscriptions. Cancel at least 24 hours before the end of the current period to avoid the next charge. Payment is charged to your Apple Account at confirmation of purchase."
    /// In place of the price when the store didn't answer or has no such
    /// product, so a reader (or App Review) isn't left with a dead button.
    static let priceFailed = "Couldn't reach the App Store."
    static let retry = "Try Again"
    static let restore = "Restore Purchases"
    static let termsTitle = "Terms of Use"
    static let privacyTitle = "Privacy Policy"
    /// Apple's standard licence agreement, which applies unless the app has its own.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    struct Feature: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
    }

    /// Under the list of what Pro adds, so it reads as what is left out.
    static let freeNote = "Everything else in NoteCode stays free."

    static var features: [Feature] { [
        Feature(id: "ads", title: "No ads", detail: "The small ad at the foot of Home and the note list goes away.", systemImage: "rectangle.slash"),
        Feature(id: "run", title: "Run code in the app", detail: "Run a C++, C, Java, Python, JavaScript, Rust or Go block and see its output and give it input, beside the page.", systemImage: "play.fill"),
        Feature(id: "ai", title: "Explain Code and Summarise Note", detail: "Apple Intelligence reads a block or a note on this \(AppInfo.deviceName). Nothing is sent anywhere.", systemImage: "sparkles"),
    ] }

    /// Whether this device can use the AI features, in a sentence, so nobody
    /// buys what they can't run. Run and no ads work everywhere.
    static func aiAvailability(_ availability: AIAvailability) -> String {
        switch availability {
        case .available:
            "Apple Intelligence is ready on this \(AppInfo.deviceName)."
        case .unavailable(let reason):
            switch reason {
            case .switchedOff:
                "Explain and Summarise are switched off in Settings › Writing."
            default:
                reason.message + " Run and no ads work either way."
            }
        }
    }

    /// The price line: "$4.99 per month", or a placeholder while the store answers.
    static func priceLine(_ product: ProProduct?) -> String {
        product.map { "\($0.price) \(period)" } ?? "Loading the price…"
    }
}

struct PaywallView: View {
    @Environment(ProStatus.self) private var pro
    @Environment(\.dismiss) private var dismiss

    /// Why it opened, in a line above the features (e.g. "Explain Code is part of Pro.").
    var reason: String?
    var aiAvailability: AIAvailability = AIAssistant.systemClient.availability

    var body: some View {
        NavigationStack {
            List {
                if let reason {
                    Section { Text(reason).foregroundStyle(.secondary) }
                }

                Section {
                    ForEach(PaywallContent.features) { feature in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title).font(.headline)
                                Text(feature.detail).font(.subheadline).foregroundStyle(.secondary)
                                if feature.id == "ai" {
                                    Text(PaywallContent.aiAvailability(aiAvailability))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .accessibilityIdentifier("paywallAIAvailability")
                                }
                            }
                        } icon: {
                            Image(systemName: feature.systemImage).foregroundStyle(.tint)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("What Pro adds")
                        .textCase(nil)
                } footer: {
                    Text(PaywallContent.freeNote)
                }

                Section {
                    if pro.isPro {
                        Label("You have Pro. Thank you.", systemImage: "checkmark.seal.fill")
                    } else if pro.productFailed {
                        HStack {
                            Text(PaywallContent.priceFailed).foregroundStyle(.secondary)
                            Spacer()
                            Button(PaywallContent.retry) { pro.loadProduct() }
                                .accessibilityIdentifier("paywallRetry")
                        }
                    } else {
                        Button {
                            Task { await pro.buy() }
                        } label: {
                            HStack {
                                Text("Subscribe")
                                Spacer()
                                if pro.phase == .buying { ProgressView() } else { Text(PaywallContent.priceLine(pro.product)).bold() }
                            }
                        }
                        .disabled(pro.product == nil || pro.phase == .buying || pro.phase == .restoring)
                        .accessibilityIdentifier("paywallSubscribe")
                    }
                    Button(PaywallContent.restore) { Task { await pro.restore() } }
                        .disabled(pro.phase == .buying || pro.phase == .restoring)
                    status
                } footer: {
                    Text(PaywallContent.renewal)
                }

                Section {
                    Link(PaywallContent.termsTitle, destination: PaywallContent.terms)
                    Link(PaywallContent.privacyTitle, destination: AppInfo.privacyPolicy)
                }
            }
            .navigationTitle(PaywallContent.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(pro.isPro ? "Done" : "Not Now") { dismiss() }
                }
            }
        }
        // The whole of it is what App Review looks for, so it isn't a small card.
        .presentationSizing(.page)
        .onAppear {
            pro.reset()
            pro.loadProduct()
        }
        .onChange(of: pro.isPro) { _, isPro in
            if isPro { AccessibilityNotification.Announcement("Welcome to NoteCode Pro").post() }
        }
    }

    @ViewBuilder private var status: some View {
        switch pro.phase {
        case .pending:
            Text("Waiting for approval. Pro turns on when it's given.").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        case .restoring:
            HStack { ProgressView(); Text("Restoring…") }
        default:
            EmptyView()
        }
    }
}
