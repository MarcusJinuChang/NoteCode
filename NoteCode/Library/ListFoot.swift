//
//  ListFoot.swift
//  NoteCode
//
//  The note list's last section: the edition's rows, the links, and the mark.
//

import SwiftUI

/// The foot of the note list (step 12 of docs/ROADMAP.md): Tip Jar, Feature
/// Request, Send Feedback and Privacy Policy, then the mark and the version as
/// a sign-off under the notes.
///
/// **A row exists only if it works**, as in Settings: the edition's rows
/// (the App Store's ad, and its tip jar once the App Store has answered with
/// its products) only when they show, the mail rows once
/// `AppInfo.feedbackAddress` is set. The policy row is always there.
struct ListFoot: View {
    /// Shows a sheet an edition's row asks for; the note list presents it.
    var present: @MainActor (ExtensionSheet) -> Void
    @Environment(\.appExtensions) private var extensions

    var body: some View {
        Section {
            ForEach(rows(with: extensions)) { $0.view }
        } footer: {
            VStack(spacing: 6) {
                NoteCodeMark()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: NoteCodeMark.cornerRadius(side: 28), style: .continuous))
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
        // The App Store's asks the store for tips again (AppExtensions).
        .task { extensions.listFootAppeared() }
    }

    /// The rows in order: the edition's first (the App Store's ad, then Tip
    /// Jar), then Feature Request, Send Feedback and Privacy Policy.
    func rows(with extensions: AppExtensions) -> [ExtensionRow] {
        var rows = extensions.listFootRows(present)
        if let url = AppInfo.featureRequestURL() {
            rows.append(ExtensionRow(id: "featureRequest") {
                Link(destination: url) {
                    Label("Feature Request", systemImage: "lightbulb")
                }
            })
        }
        if let url = AppInfo.feedbackURL() {
            rows.append(ExtensionRow(id: "sendFeedback") {
                Link(destination: url) {
                    Label("Send Feedback", systemImage: "envelope")
                }
            })
        }
        rows.append(ExtensionRow(id: "privacyPolicy") {
            Link(destination: AppInfo.privacyPolicy) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        })
        return rows
    }
}
