//
//  AboutSettings.swift
//  NoteCode
//
//  Settings › Help and About (split out of SettingsView.swift).
//

import SwiftUI

struct AboutSettings: View {
    var onOpenWelcomeNote: () -> Void
    var onShowWelcomeScreen: () -> Void
    @Environment(ProStatus.self) private var pro: ProStatus?
    @State private var consent = AdConsent.shared

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    NoteCodeMark()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 84 * 0.2237, style: .continuous))
                        .accessibilityHidden(true)
                    Text("NoteCode")
                        .font(.title.bold())
                        .tracking(-0.03 * 28)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                // A new note each time it's asked for; the first launch's
                // copy, if it's still there, is left alone.
                Button("Welcome Note", action: onOpenWelcomeNote)
                    .accessibilityIdentifier("welcomeNoteButton")
                // The title screen of a first launch, shown again.
                Button("Welcome Screen", action: onShowWelcomeScreen)
                    .accessibilityIdentifier("welcomeScreenButton")
                if let feedback = AppInfo.feedbackURL() {
                    Link("Send Feedback", destination: feedback)
                }
                Link("Privacy Policy", destination: AppInfo.privacyPolicy)
                // Where the law lets the reader change their answer to
                // Google's consent form; UMP says where (AdConsent).
                if consent.privacyOptionsRequired {
                    Button("Ad Privacy Options") { Task { await consent.showPrivacyOptions() } }
                        .accessibilityIdentifier("adPrivacyOptionsButton")
                }
                NavigationLink("Acknowledgements") { AcknowledgementsPage() }
                LabeledContent("Version", value: AppInfo.versionString())
            }
        }
        .navigationTitle("Help and About")
        .task { await consent.settingsAppeared(pro: pro) }
    }
}

private struct AcknowledgementsPage: View {
    var body: some View {
        ScrollView {
            Text(AppInfo.acknowledgements() ?? "The licence text could not be loaded.")
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Acknowledgements")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
