//
//  AssistantFeature.swift
//  NoteCode
//
//  The on-device assistant as an editor feature: Explain Block in a code
//  block's edit menu and the options row, Summarise Note in •••, the result
//  sheet and the assistant's paywall, and Insert Below.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

@MainActor
final class AssistantFeature: EditorFeature {

    /// The editor this feature belongs to, which keeps it.
    private(set) weak var editor: NoteEditor?

    /// The assistant (Explain Code, Summarise Note). One per note, like the
    /// editor; its settings arrive through `AIFeatureSettings.apply(to:)`.
    let ai: AIAssistant

    init(editor: NoteEditor, ai: AIAssistant) {
        self.editor = editor
        self.ai = ai
    }

    /// The App Store edition's factory; a test passes its own assistant.
    static func factory(ai: @escaping @MainActor @Sendable () -> AIAssistant = systemWithSettings) -> EditorFeatureFactory {
        { editor in AssistantFeature(editor: editor, ai: ai()) }
    }

    /// The device's model with the saved settings already applied, so the
    /// menus are right from the page's first frame; the page accessory keeps
    /// them current after that.
    private static func systemWithSettings() -> AIAssistant {
        let ai = AIAssistant.system()
        AIFeatureSettings(defaults: .standard).apply(to: ai)
        return ai
    }

    // MARK: Actions

    func actions(for target: EditorActionTarget) -> [EditorAction] {
        // Left out when it is switched off or this iPad can never run it;
        // otherwise the sheet says why not.
        guard ai.offersFeatures else { return [] }
        switch target {
        case .codeBlock(let block):
            guard !block.isOutput else { return [] }
            return [EditorAction(
                id: "explainBlock",
                title: ai.isPro() ? "Explain Block" : "Explain Block (Pro)",
                symbol: AIAction.explainBlock.systemImage,
                placement: .codeBlockMenu,
                perform: { [weak self] in self?.explain(block) }
            )]
        case .codeBlockAtCaret:
            return [EditorAction(
                id: "explainBlockAtCaret",
                title: "Explain",
                label: "Explain Code Block",
                symbol: AIAction.explainBlock.systemImage,
                placement: .codeBlockRow,
                rowWidth: 58,
                perform: { [weak self] in
                    guard let self, let block = editor?.codeBlockAtCaret else { return }
                    explain(block)
                }
            )]
        case .note(let title):
            return [EditorAction(
                id: "summariseNote",
                title: AIAction.summariseNote.menuTitle(marksPro: !ai.isPro()),
                symbol: AIAction.summariseNote.systemImage,
                placement: .noteMenu,
                isAvailable: editor?.mode == .text,
                perform: { [weak self] in self?.summariseNote(title: title) }
            )]
        }
    }

    func pageAccessory() -> AnyView {
        AnyView(AssistantPageAccessory(assistant: self))
    }

    // MARK: The on-device assistant

    /// Explain Code: opens the assistant's sheet on a block.
    func explain(_ target: CodeBlockTarget) {
        guard !target.isOutput, !target.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ai.begin(AIPrompts.explainJob(
            code: target.code,
            languageName: target.language?.displayName,
            insertionOffset: min(NSMaxRange(target.range), editor?.textView?.textStorage.length ?? NSMaxRange(target.range)),
            contextTokens: ai.contextTokens,
            length: ai.settings.length
        ))
    }

    /// Summarise Note: opens the assistant's sheet on the note's text.
    func summariseNote(title: String) {
        guard let editor, let textView = editor.textView else { return }
        let text = textView.text ?? ""
        ai.begin(AIPrompts.summariseJob(
            text: text,
            title: title,
            insertionOffset: AIInsertion.anchor(caret: textView.selectedRange.location, in: text as NSString, codeRanges: editor.codeRanges),
            contextTokens: ai.contextTokens,
            length: ai.settings.length
        ))
    }

    /// Whether Insert Below can write: text mode, and not a locked note.
    var canInsertAnswer: Bool {
        guard let editor else { return false }
        return editor.mode == .text && !editor.isTextLocked && editor.textView != nil
    }

    /// Insert Below: the answer as a quote or an output block under the
    /// block or line it was asked about. One edit through the text view, so
    /// one undo step. Returns whether it wrote anything.
    @discardableResult
    func insertAnswer(_ answer: String, style: AIInsertStyle, at anchor: Int) -> Bool {
        guard canInsertAnswer, let editor else { return false }
        var wrote = false
        editor.perform { text, _ in
            let edit = AIInsertion.edit(inserting: answer, style: style, at: anchor, in: text as NSString)
            wrote = edit != nil
            return edit
        }
        return wrote
    }
}

/// Behind the note's page: the result sheet, the assistant's paywall, and
/// Settings › Writing › On-Device Assistant handed to the assistant.
private struct AssistantPageAccessory: View {
    let assistant: AssistantFeature

    @AppStorage(AIFeatureSettings.enabledKey) private var aiEnabled = true
    @AppStorage(AIFeatureSettings.lengthKey) private var aiLength = AIAnswerLength.standard.rawValue
    @AppStorage(AIFeatureSettings.insertStyleKey) private var aiInsertStyle = AIInsertStyle.quote.rawValue

    private var aiSettings: AIFeatureSettings {
        AIFeatureSettings(isEnabled: aiEnabled, length: aiLength, insertStyle: aiInsertStyle)
    }

    private var ai: AIAssistant { assistant.ai }

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .sheet(item: Binding(
                get: { ai.job },
                set: { if $0 == nil { ai.dismiss() } }
            )) { job in
                AIResultSheet(assistant: assistant, job: job)
            }
            .sheet(isPresented: Binding(get: { ai.needsPro }, set: { ai.needsPro = $0 })) {
                PaywallView(reason: ProGate.Reason.assistant)
            }
            .onChange(of: aiSettings, initial: true) { _, settings in
                settings.apply(to: ai)
            }
    }
}

#endif
