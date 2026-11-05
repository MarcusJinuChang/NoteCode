//
//  EditorFeature.swift
//  NoteCode
//
//  What an edition adds to a note's editor: actions in its menus and rows,
//  and whatever the page shows for them (docs/refactor/2X-seam.md › 2X4a).
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// Where an action is offered.
enum EditorActionPlacement: Equatable, Sendable {
    /// A code block's edit menu, after Run, Copy and Share.
    case codeBlockMenu
    /// The text options row's code controls, after + Output.
    case codeBlockRow
    /// The note's ••• menu, after Find in Note.
    case noteMenu
}

/// What an action is asked about.
enum EditorActionTarget {
    /// The code block an edit menu was opened on.
    case codeBlock(CodeBlockTarget)
    /// The code block the caret is in when the action is chosen: the options
    /// row's controls stay up while the caret moves between blocks, so the
    /// block is read on the tap (`NoteEditor.codeBlockAtCaret`), not when the
    /// row is drawn.
    case codeBlockAtCaret
    /// The whole note, with the title it shows.
    case note(title: String)
}

/// One thing a feature offers in the editor's menus or rows.
struct EditorAction: Identifiable {
    var id: String
    /// The name shown. It may depend on Pro, as "Explain Block (Pro)" does.
    var title: String
    /// The accessibility label, where it says more than the title.
    var label: String?
    var symbol: String
    var placement: EditorActionPlacement
    /// The hit width along the options row, for `.codeBlockRow`.
    var rowWidth: CGFloat?
    /// Shown but dimmed when false.
    var isAvailable = true
    var perform: @MainActor () -> Void
}

/// Something an edition adds to a note's editor. Made from the editor
/// (`NoteEditor(features:)`), one per note, and kept by it.
@MainActor
protocol EditorFeature: AnyObject {
    /// The actions offered on `target`, each with its placement, in the
    /// order they are shown after the editor's own items.
    func actions(for target: EditorActionTarget) -> [EditorAction]

    /// A view kept behind the note's page while it is open: where a feature
    /// hangs its sheets and watches its settings. Behind the page, not
    /// around it, so installing a feature never rebuilds the page.
    func pageAccessory() -> AnyView

    /// An item in the note's top bar, before Share, or nil for none. The
    /// page puts it in a `.primaryAction` item of its own.
    func topBarItem(in layout: EditorPageLayout) -> AnyView?

    /// A panel at the page's trailing edge, beside it: whatever width it
    /// takes comes out of the page's area. Empty while it shows nothing; it
    /// brings its own transition.
    func sidePanel(in layout: EditorPageLayout) -> AnyView

    /// A block's Run, from its button, the edit menu or ⌘R, once its
    /// language is known to run. True when the feature took it; otherwise
    /// the next feature is asked, and then the block opens on a compiler
    /// site (`CodeDestination`).
    func run(_ target: CodeBlockTarget, from textView: UITextView) -> Bool

    /// The note's code blocks, after each restyle (changed or not).
    func blocksDidChange(_ targets: [CodeBlockTarget])

    /// The text view's coordinator is connected to the editor. Also called
    /// when the feature is installed after that.
    func connect(_ services: EditorServices)
}

extension EditorFeature {
    func actions(for target: EditorActionTarget) -> [EditorAction] { [] }
    func pageAccessory() -> AnyView { AnyView(EmptyView()) }
    func topBarItem(in layout: EditorPageLayout) -> AnyView? { nil }
    func sidePanel(in layout: EditorPageLayout) -> AnyView { AnyView(EmptyView()) }
    func run(_ target: CodeBlockTarget, from textView: UITextView) -> Bool { false }
    func blocksDidChange(_ targets: [CodeBlockTarget]) {}
    func connect(_ services: EditorServices) {}
}

/// What the note's page says about the room it has, for a feature's top-bar
/// item and side panel.
struct EditorPageLayout: Equatable {
    /// A compact width: the hotbar at the bottom, and no room beside the page.
    var isCompact: Bool
    /// The window's width, measured by the page; 0 until it is known.
    var windowWidth: CGFloat
}

/// What the text view's coordinator does for a feature: general services,
/// none of which knows about any feature.
struct EditorServices {
    /// The note's text, read as the parser reads it (`nativeUTF8`).
    var text: @MainActor () -> String
    /// The note's code blocks, as they are now.
    var blocks: @MainActor () -> [CodeBlockTarget]
    /// Opens code on a compiler site, as Run does with no feature.
    var openAtSite: @MainActor (_ code: String, _ language: CodeLanguage) -> Void
    /// Applies an edit as typing does: one undo step, restyled, saved.
    var apply: @MainActor (TextEdit) -> Void
    /// The caret at a UTF-16 offset of the note, in view, with the keyboard up.
    var placeCaret: @MainActor (_ offset: Int) -> Void
}

/// Makes a feature for an editor.
typealias EditorFeatureFactory = @MainActor @Sendable (NoteEditor) -> any EditorFeature

#endif
