//
//  ListFoot.swift
//  NoteCode
//
//  The note list's last section: the tip jar, the links, and the mark.
//

import SwiftUI

/// The foot of the note list (step 12 of docs/ROADMAP.md): Tip Jar, Feature
/// Request, Send Feedback and Privacy Policy, then the mark and the version as
/// a sign-off under the notes.
///
/// **A row exists only if it works**, as in Settings: the tip jar once the
/// App Store has answered with its products, the mail rows once
/// `AppInfo.feedbackAddress` is set, the policy once `AppInfo.privacyPolicy`
/// is. Until then the foot is the mark alone.
struct ListFoot: View {
    /// The tip jar, or `nil` where there is none (previews, tests).
    var tipJar: TipJar?
    var onOpenTipJar: () -> Void

    var body: some View {
        Section {
            if let tipJar, tipJar.isAvailable {
                Button(action: onOpenTipJar) {
                    Label("Tip Jar", systemImage: "heart")
                }
                .accessibilityIdentifier("tipJarRow")
            }
            if let url = AppInfo.featureRequestURL() {
                Link(destination: url) {
                    Label("Feature Request", systemImage: "lightbulb")
                }
            }
            if let url = AppInfo.feedbackURL() {
                Link(destination: url) {
                    Label("Send Feedback", systemImage: "envelope")
                }
            }
            if let url = AppInfo.privacyPolicy {
                Link(destination: url) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
        } footer: {
            VStack(spacing: 6) {
                NoteCodeMark()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 28 * 0.2237, style: .continuous))
                    .accessibilityHidden(true)
                Text("NoteCode \(AppInfo.versionString())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
        }
        // Rows here open things; none is a note, so none is ever selected.
        .buttonStyle(.plain)
        .selectionDisabled()
        // Asks the store again if it had no answer at launch, so a slow
        // store doesn't hide the jar until the next launch.
        .task { tipJar?.load() }
    }
}
