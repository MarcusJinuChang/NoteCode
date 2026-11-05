//
//  NoteEditor+Run.swift
//  NoteCode
//
//  The editor's side of Run: running a block in the panel, the
//  subscription's 402, and scrolling to a block.
//

#if canImport(UIKit)

import SwiftUI

extension NoteEditor {

    /// Runs a block in the panel: opens it on that block and starts the run.
    /// The caller has passed the gate (`RunRoute`).
    func runInApp(_ target: CodeBlockTarget) {
        guard let block = run.blocks.first(where: { $0.ordinal == target.id.ordinal }) else { return }
        run.choose(block)
        run.tab = .output
        withAnimation(.snappy) { run.isOpen = true; run.isCollapsed = false }
        run.run(transaction: ProGate.signedTransaction)
    }

    /// Wires the session to the subscription: a 402 means the subscription
    /// ended without the app noticing, so it is re-read and the paywall opens.
    func connectRun() {
        run.onNotSubscribed = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await ProGate.refresh()
                self.onRunNeedsPro?()
            }
        }
    }

    /// The Run panel's chips: the note scrolls to a block's opening fence.
    func scroll(toBlock block: RunBlock) {
        page?.scroll(toLineAt: block.location)
    }
}

#endif
