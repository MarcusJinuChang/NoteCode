//
//  NoteSession.swift
//  NoteCode
//
//  What one open note keeps beside its page: the editor and the ink saver.
//  Both are made when first read, not when `PageDetailView` is initialised.
//

#if canImport(UIKit)
import SwiftData
import SwiftUI

/// SwiftUI runs a view's `init` far more often than it keeps the state that
/// `init` builds, so an `@State` holding a `NoteEditor` allocated one, and a
/// `DrawingSaveScheduler`, on each. This holder is what the view keeps; it
/// makes them on first read, which only a view that is kept ever does
/// (`NoteSessionTests` counts them).
@MainActor
final class NoteSession {
    private let page: Page
    private var madeEditor: NoteEditor?
    private var madeInkSaver: DrawingSaveScheduler?

    /// How many editors and savers sessions have made, for the test.
    private(set) static var editorsMade = 0
    private(set) static var inkSaversMade = 0

    init(page: Page, editor: NoteEditor? = nil) {
        self.page = page
        madeEditor = editor
    }

    /// The note's editor.
    var editor: NoteEditor {
        if let madeEditor { return madeEditor }
        let editor = NoteEditor()
        Self.editorsMade += 1
        madeEditor = editor
        return editor
    }

    /// Saves this note's ink. One per open note, like the editor. The ink is
    /// read when the page is made, not here.
    var inkSaver: DrawingSaveScheduler {
        if let madeInkSaver { return madeInkSaver }
        let saver = DrawingSaveScheduler(page: page)
        Self.inkSaversMade += 1
        madeInkSaver = saver
        return saver
    }
}

/// Saving the note's ink as the page goes away or the app leaves the screen.
struct NoteInkLifecycle: ViewModifier {
    let editor: NoteEditor
    let inkSaver: DrawingSaveScheduler

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // Ink drawn just before leaving would otherwise wait out the
            // pause after the page is gone.
            .onDisappear { [editor, inkSaver] in
                // Strokes are taken into the ink off the main thread, and the
                // last few may still be on their way.
                editor.commitInk()
                Task { await inkSaver.flush() }
            }
            // Not only on reaching the background. Swiping the app away in the
            // switcher goes from inactive straight to terminated.
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                editor.commitInk()
                inkSaver.flushBeforeSuspending { [modelContext] in
                    // The store autosaves on its own schedule, which may not
                    // come round again before the app is suspended or killed.
                    try? modelContext.save()
                }
            }
    }
}
#endif
