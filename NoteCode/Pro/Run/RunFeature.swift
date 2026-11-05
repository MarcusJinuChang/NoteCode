//
//  RunFeature.swift
//  NoteCode
//
//  Run in the app as an editor feature: the gate on a block's Run, the
//  note's Run panel state, and what the panel writes back (Keep in Note,
//  a compile error's line). Without it, Run opens a compiler site.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

@MainActor
final class RunFeature: EditorFeature {

    /// The editor this feature belongs to, which keeps it.
    private(set) weak var editor: NoteEditor?

    /// The Run panel's state for this note (RunPanel). Its runner is set
    /// here, as the feature is made, so whether Run exists is known as soon
    /// as the editor has the feature (`NoteEditor.features` is observed).
    let session = RunSession()

    /// Opens the paywall: a free reader's Run, or a 402. The page's Run host
    /// sets it (`RunPanelHost`).
    var onNeedsPro: (() -> Void)?

    private let isPro: @MainActor () -> Bool
    private let transaction: @MainActor () -> String
    private var services: EditorServices?

    init(
        editor: NoteEditor,
        runner: (any CodeRunning)?,
        isPro: @escaping @MainActor () -> Bool,
        transaction: @escaping @MainActor () -> String,
        refresh: @escaping @MainActor () async -> Void
    ) {
        self.editor = editor
        self.isPro = isPro
        self.transaction = transaction
        session.runner = runner
        // A 402 means the subscription ended without the app noticing, so it
        // is re-read and the paywall opens.
        session.onNotSubscribed = { [weak self] in
            Task { @MainActor in
                await refresh()
                self?.onNeedsPro?()
            }
        }
        session.openAtSite = { [weak self] block in
            self?.services?.openAtSite(block.code, block.language)
        }
        session.keepInNote = { [weak self] ordinal, output in
            self?.keepInNote(output, forBlockAt: ordinal)
        }
        session.showLine = { [weak self] block, line in
            self?.showLine(line, ofBlockAt: block.ordinal)
        }
    }

    /// The App Store edition's factory; a test passes its own runner and
    /// Pro state, so nothing depends on `ProStatus.shared`.
    static func factory(
        runner: @escaping @MainActor @Sendable () -> (any CodeRunning)? = { RunServiceFactory.make() },
        isPro: @escaping @MainActor @Sendable () -> Bool = { ProGate.isPro },
        transaction: @escaping @MainActor @Sendable () -> String = { ProGate.signedTransaction },
        refresh: @escaping @MainActor @Sendable () async -> Void = { await ProGate.refresh() }
    ) -> EditorFeatureFactory {
        { editor in
            RunFeature(editor: editor, runner: runner(), isPro: isPro, transaction: transaction, refresh: refresh)
        }
    }

    // MARK: The editor's hooks

    func connect(_ services: EditorServices) {
        self.services = services
        session.update(blocks: services.blocks())
    }

    func blocksDidChange(_ targets: [CodeBlockTarget]) {
        session.update(blocks: targets)
    }

    /// The gate comes first (R4): a free reader's Run opens the paywall and
    /// does nothing else. Without a service none of this exists, and the
    /// block goes to a site.
    func run(_ target: CodeBlockTarget, from textView: UITextView) -> Bool {
        switch RunRoute.route(hasRunner: session.isAvailable, isPro: isPro()) {
        case .paywall:
            onNeedsPro?()
            return true
        case .inApp:
            textView.resignFirstResponder()
            runInApp(target)
            return true
        case .redirect:
            return false
        }
    }

    // MARK: Running

    /// Runs a block in the panel: opens it on that block and starts the run.
    /// The caller has passed the gate (`RunRoute`).
    func runInApp(_ target: CodeBlockTarget) {
        guard let block = session.blocks.first(where: { $0.ordinal == target.id.ordinal }) else { return }
        session.choose(block)
        session.tab = .output
        withAnimation(.snappy) { session.isOpen = true; session.isCollapsed = false }
        session.run(transaction: transaction())
    }

    // MARK: Back into the note

    /// Keep in Note: the run's output as an ```` ```output ```` block under
    /// the code, or in place of the one already there. One edit, so one
    /// undo step. Not in a locked note.
    func keepInNote(_ output: String, forBlockAt ordinal: Int) {
        guard let services, editor?.isTextLocked != true else { return }
        let source = services.text()
        guard let edit = KeepInNote.edit(output: output, forBlockAt: ordinal, in: source, targets: services.blocks()) else { return }
        services.apply(edit)
    }

    /// A compile-error link: the caret on that line of the block, in view.
    func showLine(_ line: Int, ofBlockAt ordinal: Int) {
        guard let services, editor?.mode == .text else { return }
        let source = services.text()
        guard let target = services.blocks().first(where: { $0.id.ordinal == ordinal && !$0.isOutput }),
              let offset = KeepInNote.caretOffset(line: line, in: target, source: source)
        else { return }
        services.placeCaret(offset)
    }
}

extension NoteEditor {
    /// This note's Run panel state, when the edition has Run.
    var run: RunSession? { feature(RunFeature.self)?.session }
}

#endif
