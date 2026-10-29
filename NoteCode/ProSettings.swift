//
//  ProSettings.swift
//  NoteCode
//
//  Settings › Pro: whether the reader has it, until when, and how to manage it.
//

import SwiftUI

struct ProSettings: View {
    @Environment(ProStatus.self) private var pro
    @State private var showsPaywall = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: pro.isPro ? "Pro" : "Free")
                if let renews = pro.expirationDate {
                    LabeledContent("Renews", value: renews.formatted(date: .long, time: .omitted))
                }
            }
            Section {
                if pro.isPro {
#if canImport(UIKit) && !os(visionOS)
                    Button("Manage Subscription") { Task { await pro.manage() } }
#endif
                } else {
                    Button("See NoteCode Pro") { showsPaywall = true }
                        .accessibilityIdentifier("seeProButton")
                }
                Button(PaywallContent.restore) { Task { await pro.restore() } }
                    .disabled(pro.phase == .restoring)
            } footer: {
                if case .failed(let message) = pro.phase { Text(message) }
            }
        }
        .navigationTitle("Pro")
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }
}
