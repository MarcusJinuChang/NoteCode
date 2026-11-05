//
//  EditorLeakTests+Run.swift
//  NoteCodeTests
//
//  The editor leak tests that reach Run, kept in Pro/ with it.
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

extension EditorLeakTests {

    private static let runFeature = RunFeature.factory(
        runner: { nil }, isPro: { false }, transaction: { "" }, refresh: {}
    )

    /// Run's feature is kept by the editor and keeps only a weak editor, so
    /// it goes with it (F1).
    @Test("A connected note with Run frees its editor, coordinator and feature")
    func connectedNoteWithRunIsFreed() async throws {
        weak var feature: RunFeature?
        let refs = Self.openConnectedNote(features: [Self.runFeature]) { harness in
            feature = harness.editor.feature(RunFeature.self)
            #expect(feature != nil)
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(refs.editor.value == nil, "NoteEditor still alive")
        #expect(refs.coordinator.value == nil, "Coordinator still alive")
        #expect(feature == nil, "RunFeature still alive")
    }

    /// Run's host, behind the note's page, sets the feature's way to the paywall.
    /// That closure is kept by the feature the editor keeps, so it mustn't
    /// hold the editor (F1).
    @Test("The Run host lets its note's editor go")
    func runHostLetsEditorGo() async throws {
        let refs = try await openRunHost()
        try await Task.sleep(for: .milliseconds(200))

        #expect(refs.editor.value == nil, "NoteEditor still alive")
        #expect(refs.feature.value == nil, "RunFeature still alive")
    }

    /// An editor with Run, behind the Run host in a window until the host
    /// has set the feature's paywall hook, then the note closed while the
    /// window stays, as leaving a note does. The window goes after the
    /// weak references are read: tearing down the whole view graph would
    /// free what closing the note alone doesn't.
    private func openRunHost() async throws -> (editor: Weak<NoteEditor>, feature: Weak<RunFeature>) {
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 800))
        let opener = RunHostOpener()
        window.rootViewController = UIHostingController(rootView: RunHostWindow(opener: opener))
        window.makeKeyAndVisible()
        defer { Self.closeLater(window) }

        let refs: (editor: Weak<NoteEditor>, feature: Weak<RunFeature>)
        do {
            let editor = NoteEditor(features: [Self.runFeature])
            let feature = try #require(editor.feature(RunFeature.self))
            opener.editor = editor
            for _ in 0..<100 where feature.onNeedsPro == nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(feature.onNeedsPro != nil, "The host never set the paywall hook")
            refs = (Weak(editor), Weak(feature))
        }
        opener.editor = nil
        try await Task.sleep(for: .milliseconds(200))
        return refs
    }

    private static func closeLater(_ window: UIWindow) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            window.rootViewController = nil
            window.isHidden = true
        }
    }
}

/// Which note the window shows, if any.
@Observable @MainActor
private final class RunHostOpener {
    var editor: NoteEditor?
}

/// A window that shows a note while it is open, and nothing once it closes.
private struct RunHostWindow: View {
    let opener: RunHostOpener

    var body: some View {
        if let editor = opener.editor {
            RunHostProbe(editor: editor)
        } else {
            Color.clear
        }
    }
}

/// The part of a note window that hosts Run, shaped as `PageDetailView`
/// has it: the editor in `@State`, each feature's side panel beside the
/// page (`sidePanelLayout`), and each feature's accessory behind it, which
/// for Run is the host with its own paywall flag.
private struct RunHostProbe: View {
    @State private var editor: NoteEditor
    @State private var windowWidth: CGFloat = 800

    init(editor: NoteEditor) {
        _editor = State(initialValue: editor)
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
            ForEach(editor.features.indices, id: \.self) { index in
                editor.features[index].sidePanel(in: EditorPageLayout(isCompact: false, windowWidth: windowWidth))
            }
        }
        .background {
            ForEach(editor.features.indices, id: \.self) { index in
                editor.features[index].pageAccessory()
            }
        }
    }
}

#endif
