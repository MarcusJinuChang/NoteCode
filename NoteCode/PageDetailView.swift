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

    /// How far the hotbar has been dragged away from its dock, mid-drag.
    @State private var dragOffset: CGSize = .zero

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
                editor: editor
            )
            .padding(reservedForHotbar)

            Hotbar(
                editor: editor,
                dock: $dock,
                onDrag: { dragOffset = $0.translation },
                onDrop: drop
            )
            .offset(dragOffset)
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
        withAnimation(.snappy) {
            dock = landing
            dragOffset = .zero
        }
    }

    /// Room kept clear along the docked edge, so the bar never covers text.
    ///
    /// Moving the bar changes the page's width, and today that re-wraps the
    /// text. Once the page lays out at one canonical width with a display
    /// scale, this becomes a scale change instead, like rotation.
    private var reservedForHotbar: EdgeInsets {
        let reserve = Hotbar.thickness + Self.hotbarMargin * 2
        return EdgeInsets(
            top: 0,
            leading: dock == .left ? reserve : 0,
            bottom: dock == .bottom ? reserve : 0,
            trailing: dock == .right ? reserve : 0
        )
    }
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
