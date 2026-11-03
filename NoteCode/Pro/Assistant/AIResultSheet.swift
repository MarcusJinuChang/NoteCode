//
//  AIResultSheet.swift
//  NoteCode
//
//  The sheet an Explain or Summarise run reports in: the answer as it is
//  written, Stop while it works, then Copy and Insert Below.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

struct AIResultSheet: View {
    var editor: NoteEditor
    var job: AIJob

    @State private var copied = false

    private var ai: AIAssistant { editor.ai }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                    Label("Apple Intelligence · on this \(AppInfo.deviceName)", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(job.action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { ai.dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    actions
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: ai.state) { _, state in announce(state) }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch ai.state {
        case .idle:
            Text("Stopped.").foregroundStyle(.secondary)
        case .unavailable(let reason):
            Label(reason.message, systemImage: "sparkles.slash")
                .foregroundStyle(.secondary)
        case .generating(let progress):
            if progress.partial.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(progress.of > 1 ? "Reading part \(progress.step) of \(progress.of)…" : "Thinking…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(progress.partial)
                    .accessibilityLabel("Answer so far")
                ProgressView()
            }
        case .done(let result):
            Text(result.text)
                .textSelection(.enabled)
            if result.wasTruncated {
                Text(job.action == .explainBlock
                    ? "The block was too long, so the middle was left out."
                    : "Only the first part of this note fit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .failed(let failure):
            Label(failure.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch ai.state {
        case .generating:
            Button("Stop", systemImage: "stop.circle") { ai.cancel() }
        case .done(let result):
            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = result.text
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            Spacer()
            Menu {
                ForEach(AIInsertStyle.allCases) { style in
                    Button(style.title) { insert(result.text, as: style) }
                }
            } label: {
                Label("Insert Below", systemImage: "text.insert")
            } primaryAction: {
                insert(result.text, as: ai.settings.insertStyle)
            }
            .disabled(!editor.canInsertAnswer)
        case .failed, .idle:
            Button("Try Again", systemImage: "arrow.clockwise") { ai.begin(job) }
        case .unavailable:
            EmptyView()
        }
    }

    private func insert(_ text: String, as style: AIInsertStyle) {
        if editor.insertAnswer(text, style: style, at: job.insertionOffset) {
            ai.dismiss()
        }
    }

    private func announce(_ state: AIState) {
        switch state {
        case .done: UIAccessibility.post(notification: .announcement, argument: "Answer ready")
        case .failed(let failure): UIAccessibility.post(notification: .announcement, argument: failure.message)
        default: break
        }
    }
}

#endif
