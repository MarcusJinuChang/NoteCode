//
//  NotePageView.swift
//  NoteCode
//
//  The page itself inside `PageDetailView`: the text view with everything it
//  is told about the note, the hotbar's room and the settings. It was the
//  first child of `PageDetailView.content`.
//

#if canImport(UIKit)
import SwiftUI

struct NotePageView: View {
    @Bindable var page: Page
    let editor: NoteEditor
    let settings: NoteViewSettings
    let inkSaver: DrawingSaveScheduler
    let dock: HotbarDock
    let insets: EdgeInsets
    let keyboardClearance: CGFloat
    let revealing: NoteSearch
    let resumingAtPage: Int?
    let onScrolled: (NoteMemory.Place) -> Void

    var body: some View {
        DocumentTextView(
            text: $page.content,
            editor: editor,
            pageConfiguration: PageConfiguration(
                pageLayout: PageLayout(orientation: page.orientation, mode: settings.viewMode),
                keyboardClearance: keyboardClearance,
                restingClearance: CanvasGeometry.restingClearance(dock: dock, footprint: Hotbar.footprint),
                areaInsets: UIEdgeInsets(
                    top: insets.top, left: insets.leading,
                    bottom: insets.bottom, right: insets.trailing
                ),
                // The hotbar's own snap, so the two move as one.
                areaAnimation: .snappy,
                inkSaver: inkSaver,
                revealing: revealing,
                resumingAtPage: resumingAtPage,
                onReadingPlaceChanged: { [weak page] place in
                    // A note made moments ago has no permanent ID until it is
                    // saved; `settledID` saves it, as the autosave would.
                    if let page, let id = page.settledID {
                        NoteMemory().setPlace(place, of: id)
                    }
                },
                minimumPageCount: page.minimumPageCount,
                onMinimumPageCountChanged: { [weak page] count in
                    if let page, count > page.minimumPageCount { page.minimumPageCount = count }
                },
                addsPagesWhileDrawing: settings.addsPagesWhileDrawing,
                onScrolled: onScrolled
            ),
            editorSettings: EditorSettings(
                showMarkdown: settings.showMarkdown,
                markerDimming: MarkerDimming(
                    headings: settings.headingMarkers, bullets: settings.bulletMarkers, checkboxes: settings.checkboxMarkers, fences: settings.fenceMarkers
                ),
                rendersMarkdown: true,
                codeSettings: CodeEditorSettings(indentWidth: settings.indentWidth, codeKeys: settings.codeKeys, lineNumbers: settings.lineNumbers),
                rewritesProse: settings.rewritesProse
            ),
            typography: NoteTypography(bodySize: page.textSize, lineSpacing: page.lineSpacing)
        )
        // Square and unbordered: the page fills its area. Nothing clips
        // it here: the page view is a scroll view, which keeps a page
        // zoomed wider than its area off the hotbar's space by itself,
        // and lets go while the page slides after the hotbar.
        .padding(insets)
        // The keyboard covers the page; it doesn't resize it. Shrinking
        // the page's area re-fit the page to a shorter space and moved
        // the text under the reader. The hotbar, a sibling, keeps the
        // keyboard's safe area and rides above it. `PageView` insets the
        // text so the caret stays clear of the keyboard.
        .ignoresSafeArea(.keyboard)
    }
}

/// What shows around the page and under the top bar.
struct NotePageSurround: ViewModifier {
    @Environment(\.displayScale) private var screenScale

    func body(content: Content) -> some View {
        content
            // The surround, behind the hotbar's reserved strips and the margins
            // around the page view too: what isn't the page is the surround, not
            // the window's own colour.
            //
            // A view that ignores every safe area, keyboard included, not
            // `.background(Color)`: that form ignores the container's safe areas
            // but not the keyboard's. This stack keeps the keyboard's, for the
            // hotbar, so it shrinks as the keyboard rises, and the surround rode
            // up with its bottom edge, the window's white showing around and
            // under the translucent keyboard (simulator, 9 October).
            .background {
                Color(PageView.surroundColor)
                    .ignoresSafeArea()
            }
            // The hairline between the top bar and the note area (W2). The page
            // never scrolls under the bar, so the system draws none.
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1 / screenScale)
                    .allowsHitTesting(false)
            }
    }
}
#endif
