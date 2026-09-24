//
//  PageDetailView.swift
//  NoteCode
//

import SwiftUI

/// One note: a header with its title, then the page, with the hotbar docked
/// to one of the page's edges.
///
/// The iOS page is DocumentTextView (TextKit 2). macOS keeps a plain
/// TextEditor and has no hotbar.
struct PageDetailView: View {
    @Bindable var page: Page

    /// Shows or hides the note list. `nil` where there's no sidebar to toggle:
    /// in a compact width the list is a screen of its own, and the back
    /// button does this job.
    var toggleSidebar: (() -> Void)? = nil

    /// Where code blocks run when a page hasn't chosen for itself. Not in the
    /// model: it is a preference about this device, not a property of a note,
    /// and it has to have a value before any page exists.
    @AppStorage(RunDestinationPreference.appDefaultKey)
    private var appDefaultDestination: String = CodeDestination.default.id

#if canImport(UIKit)
    @State private var editor = NoteEditor()

    @AppStorage(HotbarDock.defaultsKey)
    private var dock: HotbarDock = .default

    /// How pages are shown. Per device, like the dock: it's how this reader
    /// likes to look at notes, and changes nothing in the note itself.
    @AppStorage(PageViewMode.defaultsKey)
    private var viewMode: PageViewMode = .default

    /// The page area the hotbar docks within, for working out where a drag lands.
    @State private var pageSize: CGSize = .zero
#endif

    /// Gap between the hotbar and the edges around it.
    private static let hotbarMargin: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
#if os(iOS)
        // The header carries the sidebar button, so the navigation bar would
        // only be a second, empty title bar.
        .toolbar(toggleSidebar == nil ? .automatic : .hidden, for: .navigationBar)
#endif
        .onChange(of: page.title) { page.modifiedAt = .now }
        .onChange(of: page.content) { page.modifiedAt = .now }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let toggleSidebar {
                    Button(action: toggleSidebar) {
                        Label("Notes", systemImage: "line.3.horizontal")
                    }
                }

                Spacer()

#if canImport(UIKit)
                PageViewMenu(mode: $viewMode)
#endif

                RunDestinationMenu(
                    pageSetting: $page.runDestination,
                    appDefault: $appDefaultDestination
                )

                // Sign in with Apple lands with the App Store release. The
                // button holds its place so the header doesn't reshuffle then.
                Button {} label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .disabled(true)
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .buttonStyle(.borderless)

            TextField("Title", text: $page.title)
                .font(.largeTitle.bold())
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: Page

#if canImport(UIKit)
    private var content: some View {
        ZStack {
            DocumentTextView(
                text: $page.content,
                runDestination: RunDestinationPreference.resolve(
                    [page.runDestination, appDefaultDestination]
                ),
                editor: editor,
                pageLayout: PageLayout(orientation: page.orientation, mode: viewMode)
            )
            // The outline is what separates the page from the hotbar's space
            // around it. Clipping to the same shape keeps anything that runs
            // past the page — ink, or a page wider than its area below the
            // minimum scale — inside the line rather than across the dock.
            .clipShape(.rect(cornerRadius: Self.pageCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Self.pageCornerRadius)
                    .strokeBorder(.separator, lineWidth: 1)
            }
            .padding(pageInsets)

            Hotbar(editor: editor, dock: $dock, onDrop: drop)
                .padding(Self.hotbarMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dock.alignment)
        }
        .coordinateSpace(.named(Hotbar.coordinateSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
    }

    /// Snaps the bar to whichever edge it was let go nearest.
    ///
    /// Uses the predicted end rather than where the finger stopped, so a flick
    /// toward an edge goes there without having to be dragged all the way.
    private func drop(_ drag: DragGesture.Value) {
        let landing = HotbarDock.nearest(to: drag.predictedEndLocation, in: pageSize)
        // The bar's drag offset springs back on its own as the gesture ends,
        // with the same animation, so the two read as one movement.
        withAnimation(.snappy) {
            dock = landing
        }
    }

    /// Where the page's outline sits.
    ///
    /// Clear of the hotbar's room on both sides, wherever the bar is — see
    /// `CanvasGeometry.hotbarReserve` — so moving the bar leaves the page
    /// exactly where and how large it was. Top and bottom keep the same gap
    /// the bar keeps from its edges, so the outline sits evenly in its space.
    private var pageInsets: EdgeInsets {
        let reserve = CanvasGeometry.hotbarReserve(
            dock: dock,
            thickness: Hotbar.thickness + Self.hotbarMargin * 2
        )
        return EdgeInsets(
            top: Self.hotbarMargin,
            leading: reserve.left,
            bottom: max(reserve.bottom, Self.hotbarMargin),
            trailing: reserve.right
        )
    }

    private static let pageCornerRadius: CGFloat = 16
#else
    private var content: some View {
        TextEditor(text: $page.content)
            .font(.body)
            .padding(.horizontal, 8)
    }
#endif
}

private extension HotbarDock {
    var alignment: Alignment {
        switch self {
        case .left:   .leading
        case .bottom: .bottom
        case .right:  .trailing
        }
    }
}
