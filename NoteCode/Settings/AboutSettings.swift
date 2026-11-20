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
    @Environment(\.appExtensions) private var extensions

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    NoteCodeMark()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: NoteCodeMark.cornerRadius(side: 84), style: .continuous))
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
                // The edition's rows (the App Store's Ad Privacy Options).
                ForEach(extensions.aboutRows()) { $0.view }
                NavigationLink("Acknowledgements") { AcknowledgementsPage() }
                LabeledContent("Version", value: AppInfo.versionString())
            }
        }
        .navigationTitle("Help and About")
        .task { await extensions.settingsAppeared() }
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
