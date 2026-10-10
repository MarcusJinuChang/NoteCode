//
//  PageDetailView.swift
//  NoteCode
//

import SwiftData
import SwiftUI

/// One note: the page, with the hotbar docked to one of its edges, under a
/// navigation bar that is the note's header.
///
/// The header is the system's: the sidebar button on the left, the title as a
/// menu (rename, pin, move, lock, info, delete), then share and •••. It was a custom view with a
/// large-title field under a row of icons; the navigation bar's own editable
/// title does the same job and is where iPad people expect to rename a
/// document.
///
/// The iOS page is DocumentTextView (TextKit 2). macOS keeps a plain
/// TextEditor and has no hotbar.
struct PageDetailView: View {
    @Bindable var page: Page

    /// The search this note was opened from, whose matches it shows as it
    /// opens. Empty when it wasn't opened from a search.
    var revealing = NoteSearch("")

    /// Closes the note and deletes it, once the reader has confirmed. `nil`
    /// where nothing can close the note, which leaves Delete out of the menu.
    var onDelete: (() -> Void)? = nil

    /// Whether to open with the title being renamed: a note just made, so
    /// its name can be typed straight away.
    var startsRenaming = false

    /// Where code blocks run when a page hasn't chosen for itself. Not in the
    /// model: it is a preference about this device, not a property of a note,
    /// and it has to have a value before any page exists.
    @AppStorage(RunDestinationPreference.appDefaultKey)
    private var appDefaultDestination: String = CodeDestination.default.id

    @Environment(\.modelContext) private var modelContext
    @Query private var folders: [Folder]

#if canImport(UIKit)
    @State private var editor = NoteEditor()

    /// Saves this note's ink. One per open note, like the editor.
    @State private var inkSaver: DrawingSaveScheduler

    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(HotbarDock.defaultsKey)
    private var dock: HotbarDock = .default

    /// How pages are shown. Per device, like the dock: it's how this reader
    /// likes to look at notes, and changes nothing in the note itself.
    @AppStorage(PageViewMode.defaultsKey)
    private var viewMode: PageViewMode = .default

    /// The page area the hotbar docks within, for working out where a drag lands.
    @State private var pageSize: CGSize = .zero

    /// What the reader has set the Pencil's double tap and squeeze to do,
    /// in Settings.
    @Environment(\.preferredPencilDoubleTapAction) private var doubleTapAction
    @Environment(\.preferredPencilSqueezeAction) private var squeezeAction

    /// Whether the ink tools are showing beside the Pencil, and where.
    @State private var showsInkTools = false
    @State private var inkToolsAnchor = UnitPoint.center
#endif

    @State private var showsInfo = false
    @State private var confirmsDelete = false
    @State private var isNamingCustomSite = false

    /// "New Folder…" in the title menu's Move to Folder, and the name typed.
    @State private var isNamingFolder = false
    @State private var typedFolderName = ""

    /// Gap between the hotbar and the edges around it.
    private static let hotbarMargin: CGFloat = 12

    init(
        page: Page,
        revealing: NoteSearch = NoteSearch(""),
        onDelete: (() -> Void)? = nil,
        startsRenaming: Bool = false
    ) {
        self.page = page
        self.revealing = revealing
        self.onDelete = onDelete
        self.startsRenaming = startsRenaming
#if canImport(UIKit)
        // Cheap: the ink is read when the page is made, not here. SwiftUI
        // builds this view far more often than it keeps a new state.
        _inkSaver = State(initialValue: DrawingSaveScheduler(page: page))
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if startsRenaming && !page.isTextLocked {
                RenameOnAppear()
            }
#if canImport(UIKit)
            if let problem = inkSaver.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
#endif
            content
        }
        .navigationTitle($page.title)
#if os(iOS)
        // A title in the bar's own line, not a large title above the page,
        // and on iPad leading, beside ☰, with the menu's chevron after it.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
#endif
        .toolbarTitleMenu {
            NoteTitleMenu(
                page: page,
                folders: folders,
                onNewFolder: {
                    typedFolderName = ""
                    isNamingFolder = true
                },
                onGetInfo: { showsInfo = true },
                onDelete: onDelete.map { _ in { confirmsDelete = true } }
            )
        }
        .toolbar { headerItems }
        .sheet(isPresented: $showsInfo) {
            NoteInfoView(page: page, pageCount: openPageCount)
        }
        .runDestinationSiteAlert(isPresented: $isNamingCustomSite, pageSetting: $page.runDestination)
        .alert("Delete “\(page.title)”?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This note and its drawing will be deleted. This can't be undone.")
        }
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Name", text: $typedFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { moveToNewFolder() }
        }
        .onChange(of: page.title) { page.modifiedAt = .now }
        .onChange(of: page.content) { page.modifiedAt = .now }
#if canImport(UIKit)
        // Before the text view exists as well as after: the editor keeps
        // the setting and applies it when the page attaches.
        .onChange(of: page.isTextLocked, initial: true) { _, locked in
            editor.setTextLocked(locked)
        }
        // Ink drawn just before leaving would otherwise wait out the pause
        // after the page is gone.
        .onDisappear { [inkSaver] in
            Task { await inkSaver.flush() }
        }
        // Not only on reaching the background. Swiping the app away in the
        // switcher goes from inactive straight to terminated.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            inkSaver.flushBeforeSuspending { [modelContext] in
                // The store autosaves on its own schedule, which may not come
                // round again before the app is suspended or killed.
                try? modelContext.save()
            }
        }
#endif
    }

    // MARK: Header

    /// Share and ••• on the right, in the label colour, not the accent,
    /// which belongs to the tools and the page. The sidebar button on the
    /// left is the system's: it opens the list over the page, and in a
    /// compact width the back button takes its place.
    @ToolbarContentBuilder
    private var headerItems: some ToolbarContent {
        // The title is the system's, so it can't carry the lock after it;
        // the lock sits beside the buttons instead, only while it's locked.
        if page.isTextLocked {
            ToolbarItem(placement: .primaryAction) {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Text Locked")
            }
        }

#if canImport(UIKit)
        ToolbarItem(placement: .primaryAction) {
            NoteShareButton(editor: editor, title: page.title)
                .tint(.primary)
        }
#endif

        ToolbarItem(placement: .primaryAction) {
            moreMenu
                .tint(.primary)
        }
    }

    /// •••: how pages are shown, where code runs, and find.
    private var moreMenu: some View {
        Menu {
#if canImport(UIKit)
            Section("View") {
                Picker("View", selection: $viewMode) {
                    ForEach(PageViewMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }
#endif

            RunDestinationMenu(
                pageSetting: $page.runDestination,
                folder: page.folder,
                appDefault: $appDefaultDestination,
                isNamingCustomSite: $isNamingCustomSite
            )

#if canImport(UIKit)
            Button("Find in Note", systemImage: "magnifyingglass") {
                editor.showFind()
            }
            // The text view answers ⌘F itself while it's typing; this is the
            // same shortcut for when it isn't, and listed in the ⌘ overlay.
            .keyboardShortcut("f", modifiers: .command)
#endif
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    private func moveToNewFolder() {
        let folder = Folder(name: Folder.name(fromTyped: typedFolderName))
        withAnimation {
            modelContext.insert(folder)
            page.folder = folder
        }
    }

    /// The open note's pages, which only the laid-out page knows.
    private var openPageCount: Int? {
#if canImport(UIKit)
        editor.pageCount
#else
        nil
#endif
    }

    // MARK: Page

#if canImport(UIKit)
    private var content: some View {
        ZStack {
            DocumentTextView(
                text: $page.content,
                runDestination: RunDestinationPreference.resolve(
                    page.runDestinationLevels(appDefault: appDefaultDestination)
                ),
                editor: editor,
                pageLayout: PageLayout(orientation: page.orientation, mode: viewMode),
                keyboardClearance: dock == .bottom ? Hotbar.thickness + Self.hotbarMargin : 0,
                inkSaver: inkSaver,
                revealing: revealing
            )
            // The page draws its own border, on the page's edges rather than
            // the area's — see PageView.outline. Clipping keeps anything that
            // runs past the area, like a page zoomed wider than it, off the
            // hotbar's space, and rounds print layout's surround.
            .clipShape(.rect(cornerRadius: PageView.outlineCornerRadius))
            .padding(pageInsets)
            // The keyboard covers the page; it doesn't resize it. Shrinking
            // the page's area re-fit the page to a shorter space and moved
            // the text under the reader. The hotbar, a sibling, keeps the
            // keyboard's safe area and rides above it. `PageView` insets the
            // text so the caret stays clear of the keyboard.
            .ignoresSafeArea(.keyboard)

            Hotbar(editor: editor, dock: $dock, onDrop: drop)
                .padding(Self.hotbarMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dock.alignment)
        }
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
        .coordinateSpace(.named(Hotbar.coordinateSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
        .onPencilDoubleTap { tap in
            respond(to: PencilResponse(doubleTapAction), at: tap.hoverPose?.anchor)
        }
        .onPencilSqueeze { phase in
            // On letting go: a squeeze held and released is one request.
            guard case .ended(let squeeze) = phase else { return }
            respond(to: PencilResponse(squeezeAction), at: squeeze.hoverPose?.anchor)
        }
        .popover(isPresented: $showsInkTools, attachmentAnchor: .point(inkToolsAnchor)) {
            InkToolPopover(editor: editor)
        }
        // What each ink tool is set to carries over from note to note.
        .modifier(InkToolPersistence(editor: editor))
    }

    /// Does what the reader has set a Pencil gesture to do, in ink mode.
    ///
    /// - Parameter anchor: where the Pencil is hovering over the page, if it
    ///   is — where the ink tools show. Without it, they show by the hotbar.
    private func respond(to response: PencilResponse, at anchor: UnitPoint?) {
        guard editor.mode == .ink else { return }
        switch response {
        case .toggleEraser:
            editor.toggleEraser()
        case .switchToPreviousTool:
            editor.switchToPreviousTool()
        case .showInkTools:
            if showsInkTools {
                showsInkTools = false
            } else {
                inkToolsAnchor = anchor ?? dock.inkToolsAnchor
                showsInkTools = true
            }
        case .nothing:
            break
        }
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

    /// The area the page is drawn in.
    ///
    /// Clear of the hotbar's room on both sides, wherever the bar is — see
    /// `CanvasGeometry.hotbarReserve` — so moving the bar leaves the page
    /// exactly where and how large it was. Top and bottom keep the same gap
    /// the bar keeps from its edges, so the page sits evenly in its space.
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

#else
    private var content: some View {
        TextEditor(text: $page.content)
            .font(.body)
            .padding(.horizontal, 8)
            .disabled(page.isTextLocked)
    }
#endif
}

#if canImport(UIKit)
extension PageDetailView {
    /// A page whose editing state the caller holds, to drive it from outside:
    /// a test switching modes and reading where the page sits.
    init(page: Page, editor: NoteEditor) {
        self.init(page: page)
        _editor = State(initialValue: editor)
    }
}
#endif

private extension HotbarDock {
    var alignment: Alignment {
        switch self {
        case .left:   .leading
        case .bottom: .bottom
        case .right:  .trailing
        }
    }

    /// Where the ink tools show when the Pencil isn't hovering: by the bar.
    var inkToolsAnchor: UnitPoint {
        switch self {
        case .left:   .leading
        case .bottom: .bottom
        case .right:  .trailing
        }
    }
}
