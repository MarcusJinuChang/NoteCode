//
//  HomeView.swift
//  NoteCode
//
//  Home: what the page area shows when no note is open (the `Home` and
//  `HomeEmpty` boards).
//

import SwiftData
import SwiftUI

/// Where the app opens: the note to carry on with, the notes edited lately, and
/// the folders. The note list stays behind the ☰, as it does over a note.
///
/// What goes where is `HomeSections`; this lays it out. It asks `ContentView`
/// to do the things only the window can (open a note, bring the list in), and
/// does the rest itself, so it works as a view of any store.
struct HomeView: View {
    /// Opens a note.
    var onOpen: (Page) -> Void
    /// A card was tapped: the note, and where the card is, so closing the
    /// note can shrink it back there (W3). Cards call this, not `onOpen`.
    var onOpenFrom: (Page, HomeLaunch) -> Void = { _, _ in }

    /// Makes a note and opens it, the way ⌘N does.
    var onNewNote: () -> Void

    /// Makes a note from a template and opens it.
    var onNewNoteFromTemplate: (NoteTemplate) -> Void = { _ in }

    /// Asks for files to import as notes.
    var onImport: () -> Void = {}

    /// Brings the note list in over Home ("Show All").
    var onShowList: () -> Void

    /// Brings the list in with this folder open.
    var onShowFolder: (Folder) -> Void

    /// Brings the list in with its search field focused.
    var onSearch: () -> Void

    /// Settings, from the gear: the list's ••• has it too, a list away.
    var onShowSettings: () -> Void = {}

    /// Makes a Welcome note and opens it, for an empty Home.
    var onOpenWelcomeNote: () -> Void

    // Every note, deleted ones included: `HomeSections` leaves those out.
    @Query(sort: \Page.modifiedAt, order: .reverse) private var pages: [Page]
    @Query private var folders: [Folder]

    @State private var editingFolder: FolderEditing?

    /// Where each card is on screen and how big Home is, kept for the note's
    /// way back (W3). Updated as cards move; read once, on a tap.
    @State private var cardFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var homeSize: CGSize = .zero

    /// What the Continue card says about its note: the languages in it, and
    /// whether it has ink. Worked out off the card's first drawing, not in
    /// `body`: ink is read from external storage, and the text is parsed.
    @State private var continueFacts: [String] = []

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    /// An iPhone or a folded Duo: one hand's width, so cards are smaller and
    /// the grids have two columns.
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
#else
    private var isCompact: Bool { false }
#endif

    private let memory = NoteMemory()

    var body: some View {
        let sections = HomeSections(pages: pages, folders: folders, lastOpened: memory.lastOpenedKey())

        Group {
            if sections.hasNoNotes {
                empty
            } else {
                populated(sections)
            }
        }
        .coordinateSpace(.named("home"))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { homeSize = $0 }
        .navigationTitle("Home")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Settings", systemImage: "gearshape", action: onShowSettings)
                    .accessibilityIdentifier("homeSettingsButton")
                Button("Search Notes", systemImage: "magnifyingglass", action: onSearch)
                    .accessibilityIdentifier("homeSearchButton")
                Button("New Note", systemImage: "plus", action: onNewNote)
                    .accessibilityIdentifier("homeToolbarNewNote")
            }
            .sharedBackgroundVisibility(.hidden)
        }
#if os(iOS)
        .toolbarBackground(BarMaterial.fill, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
#endif
        .sheet(item: $editingFolder) { editing in
            FolderEditor(editing: editing)
        }
    }

    // MARK: Home

    private func populated(_ sections: HomeSections) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let page = sections.continuing {
                    Text("Continue")
                        .font(.title2.bold())
                        .padding(.top, 18)
                        .accessibilityAddTraits(.isHeader)
                    continueCard(page)
                }

                if !sections.recent.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Recent")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Show All", action: onShowList)
                            .font(.body)
                            .accessibilityIdentifier("homeShowAll")
                    }
                    .padding(.top, 18)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: isCompact ? 150 : 190), spacing: gridSpacing)], spacing: gridSpacing) {
                        ForEach(sections.recent) { page in
                            recentCard(page)
                        }
                    }
                }

                Text("Folders")
                    .font(.title2.bold())
                    .padding(.top, 18)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: isCompact ? 2 : 4), spacing: 16) {
                    ForEach(sections.folders) { tile in
                        folderTile(tile)
                    }
                    newFolderTile
                }

                // Side by side on an iPad; on a phone they don't fit across.
                (isCompact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                    Button(action: onNewNote) {
                        Label("New Note", systemImage: "plus")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 48)
                            .accentFill(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("homeNewNote")

                    fromTemplate
                    importButton
                }
                .padding(.top, 26)
            }
            .frame(maxWidth: 1232, alignment: .leading)
            .padding(.horizontal, isCompact ? 16 : 40)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(HomePalette.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 14) {
            NoteCodeMark()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 44 * 0.2237, style: .continuous))
                .accessibilityHidden(true)
            Text("NoteCode")
                .font(.largeTitle.bold())
                .tracking(-0.02 * 34)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !isCompact {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gridSpacing: CGFloat { isCompact ? 12 : 24 }

    // MARK: Cards

    private func open(_ page: Page) {
        if let card = cardFrames[page.persistentModelID] {
            onOpenFrom(page, HomeLaunch(card: card, container: homeSize))
        } else {
            onOpen(page)
        }
    }

    private func continueCard(_ page: Page) -> some View {
        let place = memory.place(of: page.persistentModelID)
        return Button {
            open(page)
        } label: {
            HStack(spacing: isCompact ? 14 : 28) {
                NoteThumbnailView(page: page)
                    .frame(width: isCompact ? 68 : 136, height: isCompact ? 88 : 176)
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

                VStack(alignment: .leading, spacing: isCompact ? 4 : 10) {
                    Text(page.title)
                        .font(isCompact ? .headline : .system(size: 26, weight: .bold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let folder = page.folder {
                            Circle()
                                .fill(Color(hex: folder.color.base))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(folder.name)
                            if !isCompact || place != nil { Text("·") }
                        }
                        if let place {
                            Text("Page \(min(place.number, place.of)) of \(place.of)")
                            if !isCompact { Text("·") }
                        }
                        // A phone's card has room for where, not when.
                        if !isCompact {
                            Text("Edited \(Text(page.modifiedAt, format: .relative(presentation: .named)))")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    // A phone's card is the note and where it was left: the
                    // card is the button, so no Open, and no room for more.
                    if !isCompact, let excerpt = HomeExcerpt.of(page.content) {
                        Text(excerpt)
                            .font(.body)
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineLimit(2)
                    }

                    if !isCompact, !continueFacts.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(continueFacts, id: \.self) { fact in
                                Text(fact)
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 26)
                                    .background(
                                        HomePalette.background,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isCompact {
                    Text("Open")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 44)
                        .accentFill(in: Capsule())
                }
            }
            .padding(.leading, isCompact ? 14 : 22)
            .padding(.trailing, isCompact ? 14 : 28)
            .padding(.vertical, isCompact ? 14 : 22)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 0 : 220)
            .background {
                // The shadow is the card shape's own, not the text's.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(HomePalette.card)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 12, y: 8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
#if os(iOS)
        .hoverEffect(.highlight)
#endif
        .accessibilityLabel(continueLabel(page, place: place))
        .accessibilityHint("Opens the note")
        .trackingFrame(of: page, in: $cardFrames)
        .accessibilityIdentifier("homeContinueCard")
        .task(id: page.modifiedAt) { continueFacts = Self.facts(of: page) }
    }

    private func continueLabel(_ page: Page, place: NoteMemory.Place?) -> String {
        var parts = ["Continue", page.title]
        if let folder = page.folder { parts.append(folder.name) }
        if let place { parts.append("page \(min(place.number, place.of)) of \(place.of)") }
        return parts.joined(separator: ", ")
    }

    /// The languages a note has code in, and "Ink" if it has any.
    private static func facts(of page: Page) -> [String] {
        var facts = NoteInfo(content: page.content).code.compactMap { $0.language?.displayName }
        if !page.drawingData.isEmpty {
            facts.append("Ink")
        }
        return facts
    }

    private func recentCard(_ page: Page) -> some View {
        Button {
            open(page)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                NoteThumbnailView(page: page, fit: .top)
                    .frame(maxWidth: .infinity)
                    .frame(height: 128)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle(of: page))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomePalette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
#if os(iOS)
        .hoverEffect(.highlight)
#endif
        .trackingFrame(of: page, in: $cardFrames)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the note")
    }

    private func subtitle(of page: Page) -> String {
        [page.folder?.name, HomeDate.label(for: page.modifiedAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func folderTile(_ tile: HomeSections.FolderTile) -> some View {
        Button {
            onShowFolder(tile.folder)
        } label: {
            HStack(spacing: 14) {
                FolderBadge(folder: tile.folder, diameter: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.folder.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("^[\(tile.noteCount) note](inflect: true)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(HomePalette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
#if os(iOS)
        .hoverEffect(.highlight)
#endif
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the folder in the note list")
    }

    private var newFolderTile: some View {
        Button {
            editingFolder = .new(moving: nil)
        } label: {
            Label("New Folder", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(Color(hex: FolderColor.orange.symbol(isDark: colorScheme == .dark)))
                .frame(maxWidth: .infinity, minHeight: 84)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(HomePalette.separator)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
#if os(iOS)
        .hoverEffect(.highlight)
#endif
        .accessibilityIdentifier("homeNewFolder")
    }

    /// From Template ▾: Lecture, Problem and Lab.
    private var fromTemplate: some View {
        Menu {
            ForEach(NoteTemplate.allCases) { template in
                Button {
                    onNewNoteFromTemplate(template)
                } label: {
                    Label(template.title, systemImage: template.systemImage)
                }
            }
        } label: {
            Label("From Template", systemImage: "doc.badge.plus")
                .font(.headline)
                .foregroundStyle(.tint)
                .padding(.horizontal, 22)
                .frame(minHeight: 48)
                .overlay { Capsule().strokeBorder(.tint, lineWidth: 1.5) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeFromTemplate")
    }

    /// Import…: notes from Files, as written, or a source file as a code block.
    private var importButton: some View {
        Button(action: onImport) {
            Label("Import", systemImage: "square.and.arrow.down")
                .font(.headline)
                .foregroundStyle(.tint)
                .padding(.horizontal, 22)
                .frame(minHeight: 48)
                .overlay { Capsule().strokeBorder(.tint, lineWidth: 1.5) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeImport")
    }

    // MARK: Empty

    /// No notes at all: the mark, an invitation, and the ways to start.
    private var empty: some View {
        ScrollView {
            VStack(spacing: 0) {
                NoteCodeMark()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 72 * 0.2237, style: .continuous))
                    .accessibilityHidden(true)
                Text("Start your first note")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.top, 22)
                    .accessibilityAddTraits(.isHeader)
                Text("Type Markdown, add code that runs, and draw on Letter pages. Folders keep each class together.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                Button(action: onNewNote) {
                    Label("New Note", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .accentFill(in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 32)
                .accessibilityIdentifier("homeEmptyNewNote")

                fromTemplate
                    .padding(.top, 14)

                importButton
                    .padding(.top, 14)

                Button("Open the Welcome Note", action: onOpenWelcomeNote)
                    .font(.body)
                    .padding(.top, 22)
                    .accessibilityIdentifier("homeEmptyWelcomeNote")
            }
            .padding(.horizontal, 56)
            .padding(.top, 56)
            .padding(.bottom, 44)
            .frame(maxWidth: 560)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(HomePalette.card)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 30, y: 24)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
        .background { DottedSurround() }
    }
}

private extension View {
    /// Keeps `page`'s card frame, in Home's coordinate space, up to date.
    func trackingFrame(of page: Page, in frames: Binding<[PersistentIdentifier: CGRect]>) -> some View {
        let id = page.persistentModelID
        return onGeometryChange(for: CGRect.self) { $0.frame(in: .named("home")) } action: { frames.wrappedValue[id] = $0 }
    }
}
