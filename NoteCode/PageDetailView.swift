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
    @Query private var folders: [Folder]

#if canImport(UIKit)
    @State private var editor = NoteEditor()
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    /// Saves this note's ink. One per open note, like the editor.
    @State private var inkSaver: DrawingSaveScheduler

    /// The page the note was last read at on this device, read once as the
    /// note opens: the page then writes its own place back as it is read.
    @State private var resumingAtPage: Int?

    @Environment(ProStatus.self) private var pro: ProStatus?

    /// The window's width, for the Run dock's half-window limit.
    @State private var windowWidth: CGFloat = 0
    /// Run was chosen by a free reader: Pro's, so it explains instead of
    /// opening. P2's paywall replaces this alert.
    @State private var showsRunIsPro = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var screenScale

    @AppStorage(HotbarDock.defaultsKey)
    private var storedDock: HotbarDock = .default

    /// In a compact width the bar is at the bottom whatever this device
    /// stored, and can't be moved; the stored edge is the iPad's, and comes
    /// back when the width does (a Duo unfolded).
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
#else
    private var isCompact: Bool { false }
#endif

    /// Where the bar is: the stored edge, or the bottom in a compact width,
    /// and never across a Duo's fold while it is partly folded
    /// (`FoldAvoidance`). Only a drag or Settings changes the stored edge.
    private var dock: HotbarDock {
        get {
            if isCompact { return .bottom }
            return FoldAvoidance.dock(storedDock, avoiding: folds, in: pageSize, band: Hotbar.footprint)
        }
        nonmutating set { if !isCompact { storedDock = newValue } }
    }

    /// The active folds over the page area, in its coordinates
    /// (`FoldReader`). None on any device but a Duo, nor on a Duo flat open.
    @State private var folds: [CGRect] = []

    /// How pages are shown. Per device, like the dock: it's how this reader
    /// likes to look at notes, and changes nothing in the note itself.
    @AppStorage(PageViewMode.defaultsKey)
    private var viewMode: PageViewMode = .default

    /// Whether a code block's backticks show only while it is edited, or
    /// always. Settings › Writing has the switch.
    @AppStorage(ShowMarkdown.defaultsKey)
    private var showMarkdown: ShowMarkdown = .whileEditing

    /// Settings › Writing › Markers: how dim each kind of visible marker is.
    @AppStorage(MarkerDimming.headingsKey) private var headingMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.bulletsKey) private var bulletMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.checkboxesKey) private var checkboxMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.fencesKey) private var fenceMarkers = MarkerLevel.dim

    /// Settings › Code: the indent width, the row of code keys, line numbers.
    @AppStorage(CodeIndent.widthKey)
    private var indentWidth = CodeIndent.defaultWidth

    @AppStorage(CodeKeys.enabledKey)
    private var codeKeys = CodeKeys.enabledByDefault

    @AppStorage(LineNumbers.defaultsKey)
    private var lineNumbers = LineNumbers.enabledByDefault

    /// Settings › Writing › Autocorrect.
    @AppStorage(TextRewritingPolicy.proseDefaultsKey)
    private var rewritesProse = TextRewritingPolicy.proseEnabledByDefault
    /// Settings › Writing › On-Device Assistant.
    @AppStorage(AIFeatureSettings.enabledKey) private var aiEnabled = true
    @AppStorage(AIFeatureSettings.lengthKey) private var aiLength = AIAnswerLength.standard.rawValue
    @AppStorage(AIFeatureSettings.insertStyleKey) private var aiInsertStyle = AIInsertStyle.quote.rawValue

    private var aiSettings: AIFeatureSettings {
        AIFeatureSettings(isEnabled: aiEnabled, length: aiLength, insertStyle: aiInsertStyle)
    }

    /// Whether the bar ticks as it lands on an edge (Settings › General).
    @AppStorage(SnapHaptic.defaultsKey)
    private var hapticOnSnap = SnapHaptic.isOnByDefault

    /// Settings › Drawing › Add Pages While Drawing.
    @AppStorage(InkPageGrowth.defaultsKey)
    private var addsPagesWhileDrawing = InkPageGrowth.defaultEnabled

    /// Counts the bar's drops; each one is a snap for the haptic to follow.
    @State private var snaps = 0

    /// The page area the hotbar docks within, for working out where a drag lands.
    @State private var pageSize: CGSize = .zero

    /// What the reader has set the Pencil's double tap and squeeze to do,
    /// in Settings.
    @Environment(\.preferredPencilDoubleTapAction) private var doubleTapAction
    @Environment(\.preferredPencilSqueezeAction) private var squeezeAction

    /// Whether the ink tools are showing beside the Pencil, and where.
    @State private var showsInkTools = false
    @State private var inkToolsAnchor = UnitPoint.center

    /// The header's outline popover (also ⌃⌘O).
    @State private var showsOutline = false

    /// The page badge: where the reader is while the note scrolls, which
    /// shows until a second after the scrolling stops.
    @State private var badge: NoteMemory.Place?
    @State private var badgeVisible = false
    @State private var badgeTimer: Task<Void, Never>?

    /// What the Link alert's field holds.
    @State private var linkAddress = ""

    /// What Custom… has typed so far.
    @State private var customSize = ""
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
        // Cheap: the ink is read when the page is made, not here. SwiftUI
        // builds this view far more often than it keeps a new state.
        _inkSaver = State(initialValue: DrawingSaveScheduler(page: page))
        _resumingAtPage = State(initialValue: Self.lastReadPage(of: page))
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
            runLayout
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
        .toolbar { headerItems }
#if os(iOS)
        // The top bar on the bar material, not the system's glass.
        .toolbarBackground(BarMaterial.fill, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
#endif

#if canImport(UIKit)
        .modifier(RunPanelHost(
            editor: editor, isCompact: isCompact, showsRunIsPro: $showsRunIsPro,
            windowWidth: $windowWidth, transaction: { pro?.signedTransaction ?? "" }, pro: pro
        ))
#endif
        .sheet(isPresented: $showsInfo) {
            NoteInfoView(page: page, pageCount: openPageCount)
        }
#if canImport(UIKit)
        .sheet(item: Binding(
            get: { editor.ai.job },
            set: { if $0 == nil { editor.ai.dismiss() } }
        )) { job in
            AIResultSheet(editor: editor, job: job)
        }
        .sheet(isPresented: Binding(get: { editor.ai.needsPro }, set: { editor.ai.needsPro = $0 })) {
            PaywallView(reason: "Explain Code and Summarise Note are part of NoteCode Pro.")
        }
        .onChange(of: aiSettings, initial: true) { _, settings in
            settings.apply(to: editor.ai)
        }
#endif
        .sheet(item: $editingFolder) { editing in
            FolderEditor(editing: editing)
        }
        .onChange(of: page.title) { page.modifiedAt = .now }
        .onChange(of: page.content) { page.modifiedAt = .now }
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
        // Custom… in the size control's list.
        .alert("Text Size", isPresented: Binding(
            get: { editor.customSizeSelection != nil },
            set: { _ in }
        )) {
            TextField("Points", text: $customSize)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { editor.cancelCustomSize() }
            Button("Set") { editor.finishCustomSize(typed: customSize) }
        } message: {
            Text("8 to 72 points.")
        }
        .onChange(of: editor.customSizeSelection != nil) { _, asking in
            if asking { customSize = editor.selectionTextSize.points.map(SpanSize.label(points:)) ?? "" }
        }
        .alert("Add Link", isPresented: Binding(
            get: { editor.linkTarget != nil },
            set: { _ in }
        )) {
            TextField("Address", text: $linkAddress)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { editor.cancelLink() }
            Button("Add") { editor.finishLink(address: linkAddress) }
        } message: {
            Text("Where the link goes.")
        }
        .onChange(of: editor.linkTarget != nil) { _, asking in
            if asking { linkAddress = "" }
        }
        // Before the text view exists as well as after: the editor keeps
        // the setting and applies it when the page attaches.
        .onChange(of: page.isTextLocked, initial: true) { _, locked in
            editor.setTextLocked(locked)
        }
        // The menu bar's shortcuts act on this note.
        .openNote(OpenNote(
            editor: editor,
            viewMode: $viewMode,
            printNote: { [editor, title = page.displayTitle] in
                Task { await editor.printNote(title: title) }
            },
            showOutline: { showsOutline = true }
        ))
        // Ink drawn just before leaving would otherwise wait out the pause
        // after the page is gone.
        .onDisappear { [inkSaver] in
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
                // The store autosaves on its own schedule, which may not come
                // round again before the app is suspended or killed.
                try? modelContext.save()
            }
        }
#endif
    }

    // MARK: Header

#if canImport(UIKit)
    /// The Notes | Run control, on the right with Share and •••. Not
    /// `.principal`, which replaces the title: the note's name and its menu
    /// went, leaving a bare chevron.
    @ToolbarContentBuilder
    private var runToggleItem: some ToolbarContent {
        if editor.run.isAvailable {
            ToolbarItem(placement: .primaryAction) {
                if isCompact {
                    // A phone's bar has no room for the switch beside the
                    // title, and the overflow menu it goes to drops a picker
                    // (iPhone 17, 31 Oct): a button lands there as a row.
                    Button(editor.run.isOpen ? "Back to Notes" : "Run", systemImage: editor.run.isOpen ? "doc.text" : "play") {
                        showRun(!editor.run.isOpen)
                    }
                } else {
                    NotesRunToggle(
                        isRun: editor.run.isOpen,
                        showsProMark: !(pro?.isPro ?? false),
                        onSelect: showRun
                    )
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func showRun(_ wantsRun: Bool) {
        if !wantsRun {
            withAnimation(.snappy) { editor.run.isOpen = false }
        } else if pro?.isPro == true {
            withAnimation(.snappy) { editor.run.isOpen = true; editor.run.isCollapsed = false }
        } else {
            showsRunIsPro = true
        }
    }

    /// The note, with the Run panel docked at its right where there is room.
    /// The panel narrows the page's area and nothing else: the page's zoom
    /// and place are its own.
    private var runLayout: some View {
        HStack(spacing: 0) {
            content
            if editor.run.isOpen, !isCompact {
                RunDock(
                    session: editor.run,
                    transaction: { pro?.signedTransaction ?? "" },
                    onShow: { editor.scroll(toBlock: $0) },
                    availableWidth: windowWidth
                )
                .transition(.move(edge: .trailing))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
    }
#endif

    /// Home beside the sidebar button; Share and ••• on the right, in the label colour, not the accent,
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

        // Beside the sidebar button, at the top left. The house goes where
        // the list's Home row was: the list is no longer where Home lives.
        if let onToggleList {
            ToolbarItem(placement: homePlacement) {
                NoteWindowControl(onToggleList: onToggleList, onGoHome: onGoHome)
            }
            .sharedBackgroundVisibility(.hidden)
        }

#if canImport(UIKit)
        runToggleItem

        ToolbarItem(placement: .primaryAction) {
            NoteShareButton(editor: editor, title: page.displayTitle, fallbackText: page.content)
                .tint(.primary)
        }
        .sharedBackgroundVisibility(.hidden)
#endif

        ToolbarItem(placement: .primaryAction) {
            moreMenu
                .tint(.primary)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    /// The top left. `.topBarLeading` is iOS's only; the Mac's leading
    /// place in a window's toolbar is `.navigation`.
    private var homePlacement: ToolbarItemPlacement {
#if os(iOS)
        .topBarLeading
#else
        .navigation
#endif
    }

    /// •••: how pages are shown, where code runs, the outline and find.
    /// About this note only; the app's settings are the list's and Home's.
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

#if canImport(UIKit)
            // Seamless adds its own pages as ink reaches the end.
            if viewMode != .seamless {
                Button("Add Page", systemImage: "plus.rectangle.on.rectangle") {
                    editor.addPage()
                }
            }

            // The note's own size, which every size in it is against. The
            // size control in the text row is the selection's.
            Menu {
                Picker("Text Size", selection: Binding(
                    get: { editor.textSize },
                    set: { editor.setTextSize($0) }
                )) {
                    ForEach(NoteTypography.sizes.reversed(), id: \.self) { size in
                        Text(size == NoteTypography.defaultSize ? "\(size) · Default" : "\(size)").tag(size)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Text Size", systemImage: "textformat.size")
            }
            .disabled(editor.mode != .text || page.isTextLocked)

            Button("Outline", systemImage: "list.bullet.indent") { showsOutline = true }

            Button("Find in Note", systemImage: "magnifyingglass") {
                editor.showFind()
            }
            // The text view answers ⌘F itself while it's typing; this is the
            // same shortcut for when it isn't, and listed in the ⌘ overlay.
            .keyboardShortcut(.find)

            if editor.ai.offersFeatures {
                Button(AIAction.summariseNote.menuTitle(marksPro: !editor.ai.isPro()), systemImage: AIAction.summariseNote.systemImage) {
                    editor.summariseNote(title: page.displayTitle)
                }
                .disabled(editor.mode != .text)
            }
#endif

            if let onShowSettings {
                Divider()
                Button("Settings", systemImage: "gearshape", action: onShowSettings)
                    .accessibilityIdentifier("noteMenuSettings")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
#if canImport(UIKit)
        // A popover off the ••• button, since one hung off a menu's items goes
        // when an item is chosen. ⌃⌘O raises the same binding.
        .popover(isPresented: $showsOutline) {
            let outline = editor.outline()
            NoteOutlineView(entries: outline.entries, current: outline.current) { entry in
                showsOutline = false
                editor.scroll(toHeading: entry)
            }
        }
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
    private var content: some View {
        ZStack {
            DocumentTextView(
                text: $page.content,
                editor: editor,
                pageLayout: PageLayout(orientation: page.orientation, mode: viewMode),
                keyboardClearance: keyboardClearance,
                restingClearance: CanvasGeometry.restingClearance(dock: dock, footprint: Hotbar.footprint),
                areaInsets: UIEdgeInsets(
                    top: pageInsets.top, left: pageInsets.leading,
                    bottom: pageInsets.bottom, right: pageInsets.trailing
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
                showMarkdown: showMarkdown,
                markerDimming: MarkerDimming(
                    headings: headingMarkers, bullets: bulletMarkers, checkboxes: checkboxMarkers, fences: fenceMarkers
                ),
                rendersMarkdown: true,
                codeSettings: CodeEditorSettings(indentWidth: indentWidth, codeKeys: codeKeys, lineNumbers: lineNumbers),
                rewritesProse: rewritesProse,
                typography: NoteTypography(bodySize: page.textSize, lineSpacing: page.lineSpacing),
                minimumPageCount: page.minimumPageCount,
                onMinimumPageCountChanged: { [weak page] count in
                    if let page, count > page.minimumPageCount { page.minimumPageCount = count }
                },
                addsPagesWhileDrawing: addsPagesWhileDrawing,
                onScrolled: noteScrolled
            )
            // Square and unbordered: the page fills its area. Nothing clips
            // it here: the page view is a scroll view, which keeps a page
            // zoomed wider than its area off the hotbar's space by itself,
            // and lets go while the page slides after the hotbar.
            .padding(pageInsets)
            // The keyboard covers the page; it doesn't resize it. Shrinking
            // the page's area re-fit the page to a shorter space and moved
            // the text under the reader. The hotbar, a sibling, keeps the
            // keyboard's safe area and rides above it. `PageView` insets the
            // text so the caret stays clear of the keyboard.
            .ignoresSafeArea(.keyboard)

            PageBadge(place: badge, isVisible: badgeVisible)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, Self.badgeInset)

            Hotbar(
                editor: editor,
                dock: Binding(get: { dock }, set: { dock = $0 }),
                onDrop: drop,
                textRowHidden: sheetCoversPage,
                isMovable: !isCompact,
                maxRowLength: maxRowLength
            )
                .padding(Hotbar.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dock.alignment)
                .sensoryFeedback(.alignment, trigger: snaps) { _, _ in hapticOnSnap }
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
        // The hairline between the top bar and the note area (W2). The page
        // never scrolls under the bar, so the system draws none.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1 / screenScale)
                .allowsHitTesting(false)
        }
        .background {
            FoldReader { found in
                if folds != found { folds = found }
            }
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
            showsTextRow: editor.mode == .text && !page.isTextLocked && !sheetCoversPage
        )
    }

    /// The note scrolled: the badge shows the page, and goes a second after
    /// the last movement.
    private func noteScrolled(to place: NoteMemory.Place) {
        if badge != place { badge = place }
        if !badgeVisible {
            withAnimation(.easeOut(duration: 0.15)) { badgeVisible = true }
        }
        badgeTimer?.cancel()
        badgeTimer = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { badgeVisible = false }
        }
    }

    /// The page this note was left at, from the device's memory. Nothing for a
    /// note that has none, or one never saved, which has no place yet.
    private static func lastReadPage(of page: Page) -> Int? {
        guard !page.persistentModelID.isTemporary,
              let place = NoteMemory().place(of: page.persistentModelID)
        else { return nil }
        return place.page
    }

    /// Does what the reader has set a Pencil gesture to do, in ink mode.
    ///
    /// - Parameter anchor: where the Pencil is hovering over the page, if it
    ///   is — where the ink tools show. Without it, they show by the hotbar.
    private func respond(to response: PencilResponse, at anchor: UnitPoint?) {
        // From text mode the gesture first switches to ink, then acts.
        editor.enterInkForPencil(response)
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
        snaps += 1
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

    private var runLayout: some View { content }
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
