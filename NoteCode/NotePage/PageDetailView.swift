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
/// document. The items are `NoteHeader`, the ••• menu `NoteMoreMenu`, the
/// Pencil's gestures `PencilGestureRouter` and the page badge
/// `PageBadgeModel`.
///
/// The iOS page is DocumentTextView (TextKit 2). macOS keeps a plain
/// TextEditor and has no hotbar.
struct PageDetailView: View {
    @Bindable var page: Page

    /// The search this note was opened from, whose matches it shows as it
    /// opens. Empty when it wasn't opened from a search.
    var revealing = NoteSearch("")

    /// Closes the note and moves it to Recently Deleted. Nothing asks first:
    /// the caller's toast can undo it. `nil` where nothing can close the note,
    /// which leaves Delete out of the menu.
    var onDelete: (() -> Void)? = nil

    /// Closes the note and shows Home: the house beside the sidebar button.
    var onGoHome: (() -> Void)? = nil

    /// Shows or hides the note list over the page: the sidebar half of the
    /// joined control at the top left. `nil` in a stack, whose back button
    /// takes the control's place.
    var onToggleList: (() -> Void)? = nil

    /// Opens the app's Settings sheet, which the window owns: ••• › Settings.
    var onShowSettings: (() -> Void)? = nil

    /// Whether to open with the title being renamed: a note just made, so
    /// its name can be typed straight away.
    var startsRenaming = false

    @Environment(\.modelContext) private var modelContext

    /// What the badge's hold and the edit date's pause are measured on
    /// (`PageBadgeModel.hold`, `ModifiedAtBatcher.pause`).
    @Environment(\.debounceClock) private var debounceClock
    @Environment(\.scenePhase) private var scenePhase

    /// Writes `modifiedAt` when typing pauses, or the note closes or leaves the screen.
    @State private var modifiedAtBatcher = ModifiedAtBatcher()
    @Query private var folders: [Folder]

#if canImport(UIKit)
    /// The note's editor and ink saver, made when first read rather than on
    /// every `init` (`NoteSession`).
    @State private var session: NoteSession
    private var editor: NoteEditor { session.editor }
    /// The edition's editor features, installed in `editor` as the page
    /// appears: `@State` is made before the environment can be read.
    @Environment(\.appExtensions) private var extensions
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    /// The page the note was last read at on this device, read once as the
    /// note opens: the page then writes its own place back as it is read.
    @State private var resumingAtPage: Int?

    /// The window's width, for the features' top-bar item and side panel
    /// (`EditorPageLayout`).
    @State private var windowWidth: CGFloat = 0


    let settings = NoteViewSettings()

    /// In a compact width the bar is at the bottom whatever this device
    /// stored, and can't be moved; the stored edge is the iPad's, and comes
    /// back when the width does (a Duo unfolded).
    @Environment(\.layoutClass) private var layoutClass
    private var isCompact: Bool { layoutClass.isCompact }

    /// Where the bar is: the stored edge, or the bottom in a compact width,
    /// and never across a Duo's fold while it is partly folded
    /// (`FoldAvoidance`). Only a drag or Settings changes the stored edge.
    private var dock: HotbarDock {
        get {
            if isCompact { return .bottom }
            return FoldAvoidance.dock(settings.storedDock, avoiding: folds, in: pageSize, band: Hotbar.footprint)
        }
        nonmutating set { if !isCompact { settings.storedDock = newValue } }
    }

    /// The active folds over the page area, in its coordinates
    /// (`FoldReader`). None on any device but a Duo, nor on a Duo flat open.
    @State private var folds: [CGRect] = []

    /// The page area the hotbar docks within, for working out where a drag lands.
    @State private var pageSize: CGSize = .zero

    /// The Pencil's gestures and the bar's drops.
    @State private var pencil = PencilGestureRouter()

    /// The header's outline popover (also ⌃⌘O).
    @State private var showsOutline = false

    /// What the menu bar's Print, View and Outline do on this note.
    @State private var noteActions = OpenNoteActions()

    /// The page badge: where the reader is while the note scrolls.
    @State private var badge = PageBadgeModel()
#else
    private var isCompact: Bool { false }
#endif

    @State private var showsInfo = false

    /// "New Folder…" in the title menu's Move to Folder: the folder editor,
    /// which moves this note into the folder it makes.
    @State private var editingFolder: FolderEditing?

    init(
        page: Page,
        revealing: NoteSearch = NoteSearch(""),
        onDelete: (() -> Void)? = nil,
        onGoHome: (() -> Void)? = nil,
        onToggleList: (() -> Void)? = nil,
        onShowSettings: (() -> Void)? = nil,
        startsRenaming: Bool = false
    ) {
        self.page = page
        self.revealing = revealing
        self.onDelete = onDelete
        self.onGoHome = onGoHome
        self.onToggleList = onToggleList
        self.onShowSettings = onShowSettings
        self.startsRenaming = startsRenaming
#if canImport(UIKit)
        // Cheap: SwiftUI builds this view far more often than it keeps a new
        // state, so the editor and the ink saver wait in `NoteSession`.
        _session = State(initialValue: NoteSession(page: page))
        _resumingAtPage = State(initialValue: Self.lastReadPage(of: page))
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if startsRenaming && !page.isTextLocked {
                RenameOnAppear()
            }
#if canImport(UIKit)
            if let problem = session.inkSaver.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
#endif
            sidePanelLayout
        }
        .navigationTitle(Binding(get: { page.displayTitle }, set: { page.rename(to: $0) }))
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
                onNewFolder: { editingFolder = .new(moving: page) },
                onGetInfo: { showsInfo = true },
                onDuplicate: { page.duplicated(in: modelContext) },
                onDelete: onDelete
            )
        }
        .toolbar { header }
#if os(iOS)
        // The top bar on the bar material, not the system's glass.
        .toolbarBackground(BarMaterial.fill, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
#endif

        .sheet(isPresented: $showsInfo) {
            NoteInfoView(page: page, pageCount: openPageCount)
        }
#if canImport(UIKit)
        // Each feature's sheets and settings, behind the page so that
        // installing one doesn't rebuild it (the assistant's result sheet
        // and paywall, Run's compact sheet and paywall).
        .background {
            ForEach(editor.features.indices, id: \.self) { index in
                editor.features[index].pageAccessory()
            }
        }
        .onAppear { editor.install(extensions.editorFeatures) }
#endif
        .sheet(item: $editingFolder) { editing in
            FolderEditor(editing: editing)
        }
        // Not at once: the date is the lists' sort key, and writing it per
        // keystroke re-sorted them as the reader typed (`ModifiedAtBatcher`).
        .onChange(of: page.title) { modifiedAtBatcher.edited(page, clock: debounceClock.clock) }
        .onChange(of: page.content) { modifiedAtBatcher.edited(page, clock: debounceClock.clock) }
        .onDisappear { modifiedAtBatcher.flush() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { modifiedAtBatcher.flush() }
        }
#if canImport(UIKit)
        // The note's text size is the page's property, and changing it isn't
        // an edit: `modifiedAt` and the undo stack stay as they are.
        .onChange(of: page.textSize, initial: true) { _, size in
            editor.syncTextSize(to: size)
        }
        .onChange(of: page.lineSpacing, initial: true) { _, spacing in
            editor.syncLineSpacing(to: spacing)
        }
        .onAppear {
            editor.commitTextSize = { [weak page = self.page] size in page?.textSize = size }
            editor.commitLineSpacing = { [weak page = self.page] spacing in page?.lineSpacing = spacing }
            editor.onBlockCopied = { [toasts] in toasts?.show("Copied") }
        }
        .modifier(NoteEditorAlerts(editor: editor))
        // Before the text view exists as well as after: the editor keeps
        // the setting and applies it when the page attaches.
        .onChange(of: page.isTextLocked, initial: true) { _, locked in
            editor.setTextLocked(locked)
        }
        // The menu bar's shortcuts act on this note.
        .openNote(OpenNote(editor: editor, actions: noteActions, viewMode: settings.viewMode))
        .onAppear {
            noteActions.printNote = { [editor, page] in
                Task { await editor.printNote(title: page.displayTitle) }
            }
            noteActions.setViewMode = { [settings] mode in settings.viewMode = mode }
            noteActions.showOutline = { showsOutline = true }
        }
        .modifier(NoteInkLifecycle(editor: editor, inkSaver: session.inkSaver))
#endif
    }

    // MARK: Header

    /// The navigation bar's items (`NoteHeader`).
    private var header: NoteHeader {
#if canImport(UIKit)
        NoteHeader(
            page: page, onToggleList: onToggleList, onGoHome: onGoHome, more: moreMenu,
            editor: editor, layout: featureLayout
        )
#else
        NoteHeader(page: page, onToggleList: onToggleList, onGoHome: onGoHome, more: moreMenu)
#endif
    }

    private var moreMenu: NoteMoreMenu {
#if canImport(UIKit)
        NoteMoreMenu(
            page: page, onShowSettings: onShowSettings,
            editor: editor, viewMode: settings.$viewMode, showsOutline: $showsOutline
        )
#else
        NoteMoreMenu(page: page, onShowSettings: onShowSettings)
#endif
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
    /// What the features are told about the page's room.
    private var featureLayout: EditorPageLayout {
        EditorPageLayout(isCompact: isCompact, windowWidth: windowWidth)
    }

    /// The note, with each feature's panel docked at its right. A panel
    /// narrows the page's area and nothing else: the page's zoom and place
    /// are its own.
    private var sidePanelLayout: some View {
        HStack(spacing: 0) {
            content
            ForEach(editor.features.indices, id: \.self) { index in
                editor.features[index].sidePanel(in: featureLayout)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
    }

    private var content: some View {
        ZStack {
            NotePageView(
                page: page, editor: editor, settings: settings, inkSaver: session.inkSaver,
                dock: dock, insets: pageInsets, keyboardClearance: keyboardClearance,
                revealing: revealing, resumingAtPage: resumingAtPage,
                onScrolled: { [badge, debounceClock] place in
                    badge.noteScrolled(to: place, clock: debounceClock.clock)
                }
            )

            PageBadge(place: badge.place, isVisible: badge.isVisible)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, Self.badgeInset)

            Hotbar(
                editor: editor,
                dock: Binding(get: { dock }, set: { dock = $0 }),
                onDrop: { drag in pencil.drop(drag, in: pageSize) { dock = $0 } },
                textRowHidden: sheetCoversPage,
                isMovable: !isCompact,
                maxRowLength: maxRowLength
            )
                .padding(Hotbar.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dock.alignment)
                .sensoryFeedback(.alignment, trigger: pencil.snaps) { _, _ in settings.hapticOnSnap }
        }
        .modifier(NotePageSurround())
        .background {
            FoldReader { found in
                if folds != found { folds = found }
            }
        }
        .coordinateSpace(.named(Hotbar.coordinateSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
        .modifier(PencilGestures(router: pencil, editor: editor, dock: dock))
    }

    /// Under the header.
    private static let badgeInset: CGFloat = 18

    /// The most an options row may take along the bar: the page area's length
    /// that way, less the bar's margin at each end. Nothing until the area has
    /// been measured.
    private var maxRowLength: CGFloat? {
        let length = dock.isVertical ? pageSize.height : pageSize.width
        return length > 0 ? length - Hotbar.margin * 2 : nil
    }

    /// Whether a sheet is over the page, which takes the text options row
    /// away: the info sheet and the folder editor.
    private var sheetCoversPage: Bool {
        showsInfo || editingFolder != nil
    }

    /// Room to leave above the keyboard for the hotbar riding up with it, and
    /// for the text options row above that, so the caret's line stays clear
    /// of both. Only for a bar docked at the bottom: at a side, nothing rides
    /// up over the page.
    private var keyboardClearance: CGFloat {
        Hotbar.keyboardClearance(
            dock: dock,
            showsTextRow: Hotbar.showsTextRow(
                isText: editor.mode == .text, isLocked: page.isTextLocked, isCovered: sheetCoversPage,
                isCompact: isCompact, wanted: editor.wantsTextRow
            )
        )
    }

    /// The page this note was left at, from the device's memory. Nothing for a
    /// note that has none, or one never saved, which has no place yet.
    private static func lastReadPage(of page: Page) -> Int? {
        guard !page.persistentModelID.isTemporary,
              let place = NoteMemory().place(of: page.persistentModelID)
        else { return nil }
        return place.page
    }

    /// The area the page is drawn in: all of the window, less the strip a bar
    /// docked to a side takes and a small buffer on the other edges — see
    /// `CanvasGeometry.areaInsets`.
    private var pageInsets: EdgeInsets {
        let insets = CanvasGeometry.areaInsets(dock: dock, side: Hotbar.footprint, buffer: Hotbar.pageBuffer)
        return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }

#else
    private var content: some View {
        TextEditor(text: $page.content)
            .font(.body)
            .padding(.horizontal, 8)
            .disabled(page.isTextLocked)
    }

    private var sidePanelLayout: some View { content }
#endif
}

#if canImport(UIKit)
extension PageDetailView {
    /// A page whose editing state the caller holds, to drive it from outside:
    /// a test switching modes and reading where the page sits.
    init(page: Page, editor: NoteEditor) {
        self.init(page: page)
        _session = State(initialValue: NoteSession(page: page, editor: editor))
    }
}
#endif
