//
//  TipJarView.swift
//  NoteCode
//

import SwiftUI

/// The tip jar's sheet, from the list's foot: three tips at the store's
/// prices, and a thank-you. Nothing is unlocked and nothing is remembered,
/// so it opens the same way every time.
struct TipJarView: View {
    let jar: TipJar
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        EmptyStateMark()
                        Text("NoteCode is made by one student. If it has helped with your classes, a tip helps keep it going.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(jar.tips) { tip in
                        Button {
                            Task { await jar.buy(tip) }
                        } label: {
                            HStack {
                                // `Color.primary`: in a list's button, the
                                // `.primary` style is the button's tint.
                                Text(tip.name)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if jar.phase == .buying(tip.id) {
                                    ProgressView()
                                } else {
                                    Text(tip.price)
                                        .bold()
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(isBuying)
                        .accessibilityLabel("\(tip.name), \(tip.price)")
                    }
                } footer: {
                    Text("A tip unlocks nothing. It's charged once, to your Apple Account.")
                }

                if hasStatus {
                    Section {
                        status
                    }
                }
            }
            .navigationTitle("Tip Jar")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: jar.phase == .thanked) { _, thanked in thanked }
        .onAppear {
            jar.reset()
            jar.load()
        }
        .onChange(of: jar.phase) { _, phase in
            if phase == .thanked {
                AccessibilityNotification.Announcement("Thank you for the tip").post()
            }
        }
    }

    private var isBuying: Bool {
        if case .buying = jar.phase { return true }
        return false
    }

    private var hasStatus: Bool {
        switch jar.phase {
        case .ready, .buying: false
        case .thanked, .pending, .failed: true
        }
    }

    /// What became of the last tip, under the tips.
    @ViewBuilder
    private var status: some View {
        switch jar.phase {
        case .ready, .buying:
            EmptyView()
        case .thanked:
            Label("Thank you!", systemImage: "heart.fill")
                .foregroundStyle(.tint)
                .font(.headline)
        case .pending:
            Label("Waiting for approval. The tip goes through once it's approved.", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}
