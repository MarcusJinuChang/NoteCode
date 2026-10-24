//
//  SettingsView.swift
//  NoteCode
//
//  Settings: a form sheet with a list of sections, each opening a page of its
//  own. Every row reads and writes the key the rest of the app already uses,
//  through the type that owns it (`HotbarDock.defaultsKey`,
//  `NoteSort.defaultsKey`, …), so there is no second copy of a preference to
//  drift from the first. A row appears only when it does something.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Opening it

private extension FocusedValues {
    /// Whether the window in front is showing Settings, so ⌘, can open it.
    @Entry var showsSettings: Binding<Bool>?
}

private extension EnvironmentValues {
    /// Whether the window Settings came from can move its hotbar: not in a
    /// compact width, where the bar stays at the bottom. The sheet's own size
    /// class isn't the window's, so the window says.
    @Entry var hotbarCanMove = true
}

extension View {
    /// Presents Settings as a form sheet, and lets ⌘, open it.
    ///
    /// - Parameter onOpenWelcomeNote: called when Help and About › Welcome
    ///   Note is chosen, after the sheet has been asked to close. The note is
    ///   opened by the window, which owns what's selected.
    /// - Parameter onShowWelcomeScreen: called when Help and About › Welcome
    ///   Screen is chosen, likewise after the sheet has been asked to close.
    /// - Parameter onExportFinished: called with the number of notes when
    ///   Notes › Export All Notes… has written them, likewise after the
    ///   sheet has been asked to close, so the window's toast isn't hidden by it.
    /// - Parameter hotbarCanMove: false in a compact width, where General
    ///   leaves out Toolbar Position and Haptic on Snap.
    func settingsSheet(
        isPresented: Binding<Bool>,
        onOpenWelcomeNote: @escaping () -> Void = {},
        onShowWelcomeScreen: @escaping () -> Void = {},
        onExportFinished: @escaping (Int) -> Void = { _ in },
        hotbarCanMove: Bool = true
    ) -> some View {
        self
            .focusedSceneValue(\.showsSettings, isPresented)
            .sheet(isPresented: isPresented) {
                SettingsView(
                    onOpenWelcomeNote: onOpenWelcomeNote,
                    onShowWelcomeScreen: onShowWelcomeScreen,
                    onExportFinished: onExportFinished
                )
                    .presentationSizing(.form)
                    .environment(\.hotbarCanMove, hotbarCanMove)
            }
    }
}

/// The ⌘, in the app's menu. A command can't see a window's state, so the
/// window in front hands it the binding (`settingsSheet`).
struct SettingsCommands: Commands {
    @FocusedValue(\.showsSettings) private var showsSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                showsSettings?.wrappedValue = true
            }
            .keyboardShortcut(.settings)
            .disabled(showsSettings == nil)
        }
    }
}

/// Applies Settings › General › Appearance to a window's content.
///
/// At the root of the scene, so a change reaches every window, its sheets and
/// the UIKit controllers presented from it, the moment the setting changes.
///
/// **On UIKit it is the window's `overrideUserInterfaceStyle`, not
/// `preferredColorScheme`.** `preferredColorScheme` puts an override on each
/// controller SwiftUI presents, and giving it `nil` afterwards doesn't take it
/// off again: with the device in dark, Light and then System left the open
/// Settings sheet light under a dark page (13 Oct). A window's override can be
/// set back to `.unspecified`, and everything presented from the window,
/// sheets and pickers included, takes its traits from it.
///
/// It carries Settings › General › Accent Colour too, since that is the same
/// kind of thing: `.tint` for SwiftUI, and the window's `tintColor` for UIKit
/// (the caret, the selection, the Run button). The default sets neither, so
/// the `AccentColor` asset and its Increase Contrast variants apply as before.
struct AppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.default
    @AppStorage(AccentPalette.defaultsKey) private var accent = ""

    func body(content: Content) -> some View {
        let custom = AccentPalette.parse(accent)
        #if canImport(UIKit)
        content
            .tint(custom.map { Color(hex: $0) })
            .background(WindowAppearance(
                style: appearance.userInterfaceStyle,
                tint: custom.map { AccentPalette.uiColor($0) }
            ))
        #else
        content
            .tint(custom.map { Color(hex: $0) })
            .preferredColorScheme(appearance.colorScheme)
        #endif
    }
}

#if canImport(UIKit)

extension AppAppearance {
    /// `.unspecified` follows the system.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light:  .light
        case .dark:   .dark
        }
    }
}

/// Sets the override of the window it is in, now and whenever it changes
/// windows.
private struct WindowAppearance: UIViewRepresentable {
    var style: UIUserInterfaceStyle
    /// `nil` leaves the window's tint as the asset catalog's accent set it.
    var tint: UIColor?

    final class Anchor: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { apply() }
        }
        var windowTint: UIColor? {
            didSet { apply() }
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            appliedTint = false
            apply()
        }
        func apply() {
            guard let window else { return }
            if window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
            // Only on a change: a dynamic tint never compares equal to what
            // the window reports back, and `nil` hands the window back to the
            // app's accent.
            guard !appliedTint || lastTint != windowTint else { return }
            window.tintColor = windowTint
            lastTint = windowTint
            appliedTint = true
        }
        private var lastTint: UIColor?
        private var appliedTint = false
    }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        anchor.style = style
        anchor.windowTint = tint
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        anchor.style = style
        anchor.windowTint = tint
    }
}

#endif

extension AppAppearance {
    /// `nil` follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

// MARK: - The list of sections

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    /// Makes the Welcome note and opens it. Settings dismisses itself first.
    var onOpenWelcomeNote: () -> Void = {}

    /// Shows the title screen again. Settings dismisses itself first.
    var onShowWelcomeScreen: () -> Void = {}

    /// Told how many notes Export All wrote. Settings dismisses itself first.
    var onExportFinished: (Int) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    GeneralSettings()
                } label: {
                    Label("General", systemImage: "gearshape")
                }
                NavigationLink {
                    NotesSettings(onExportFinished: { count in
                        dismiss()
                        onExportFinished(count)
                    })
                } label: {
                    Label("Notes", systemImage: "note.text")
                }
                NavigationLink {
                    WritingSettings()
                } label: {
                    Label("Writing", systemImage: "textformat")
                }
                NavigationLink {
                    CodeSettings()
                } label: {
                    Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
#if canImport(UIKit)
                NavigationLink {
                    DrawingSettings()
                } label: {
                    Label("Drawing", systemImage: "pencil.tip")
                }
#endif
                NavigationLink {
                    AboutSettings(
                        onOpenWelcomeNote: {
                            dismiss()
                            onOpenWelcomeNote()
                        },
                        onShowWelcomeScreen: {
                            dismiss()
                            onShowWelcomeScreen()
                        }
                    )
                } label: {
                    Label("Help and About", systemImage: "questionmark.circle")
                }
            }
            .navigationTitle("Settings")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.default
    @AppStorage(AccentPalette.defaultsKey) private var accent = ""
#if canImport(UIKit)
    @AppStorage(HotbarDock.defaultsKey) private var dock = HotbarDock.default
    @AppStorage(SnapHaptic.defaultsKey) private var hapticOnSnap = SnapHaptic.isOnByDefault
    @Environment(\.hotbarCanMove) private var hotbarCanMove
    @AppStorage(IconStyle.defaultsKey) private var iconStyle = IconStyle()
#endif

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.title) }
                }
            }

            Section {
                ColorPicker("Accent Colour", selection: accentColor, supportsOpacity: false)
                if AccentPalette.parse(accent) != nil {
                    Button("Reset to Orange") { accent = "" }
                }
            } footer: {
                Text("Controls, the caret and selection, checked boxes, the selected note and links. Links are darkened or lightened as needed to stay readable.")
            }
#if canImport(UIKit)
            AppIconSection()

            Section {
                Picker("Toolbar Icons", selection: $iconStyle.isDrawn) {
                    Text("NoteCode").tag(true)
                    Text("System").tag(false)
                }
                if iconStyle.isDrawn {
                    Picker("Icon Weight", selection: $iconStyle.weight) {
                        ForEach(IconWeight.allCases, id: \.self) { Text($0.title) }
                    }
                }
            } footer: {
                Text("The hotbar's and its rows' icons. Increase Contrast makes the drawn ones a step heavier.")
            }

            // The Mac has no hotbar: its editor is text only. A phone's bar
            // stays at the bottom, so there is nothing to set there.
            if hotbarCanMove {
                Section {
                    Picker("Toolbar Position", selection: $dock) {
                        ForEach(HotbarDock.allCases, id: \.self) { Text($0.title) }
                    }
                    Toggle("Haptic on Snap", isOn: $hapticOnSnap)
                } footer: {
                    Text("Toolbar Position moves the bar without dragging it. Dragging the bar's grip to an edge does the same.")
                }
            }
#endif
        }
        .navigationTitle("General")
    }

    /// The picker's colour, written back as the stored hex. Choosing the
    /// orange itself stores nothing (`AccentPalette.parse`).
    private var accentColor: Binding<Color> {
        Binding {
            Color(hex: AccentPalette.parse(accent) ?? AccentPalette.defaultHex)
        } set: { color in
            accent = AccentPalette.string(for: AccentPalette.hex(of: color))
        }
    }
}

#if canImport(UIKit)
/// Settings › General › App Icon: each icon drawn as a choice, the showing one
/// ticked. Hidden where the system doesn't allow a change, rather than shown
/// and doing nothing.
///
/// What's showing is read from `UIApplication.alternateIconName` as the
/// section appears and after every change, never kept in a setting of its
/// own. iOS shows its own "You have changed the icon" alert on a change; it
/// can't be turned off without private API.
private struct AppIconSection: View {
    @State private var current = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            Section("App Icon") {
                ForEach(AppIconChoice.allCases) { choice in
                    Button {
                        select(choice)
                    } label: {
                        HStack(spacing: 14) {
                            NoteCodeMark(icon: choice)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 44 * 0.2237, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 44 * 0.2237, style: .continuous)
                                        .strokeBorder(.separator, lineWidth: 0.5)
                                }
                                .accessibilityHidden(true)
                            Text(choice.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if choice == current {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(choice == current ? .isSelected : [])
                }
            }
        }
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != current else { return }
        Task {
            // Throws when the system refuses (an icon name this build doesn't
            // carry); the tick then goes back to what is really showing.
            try? await UIApplication.shared.setAlternateIconName(choice.alternateIconName)
            current = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
        }
    }
}
#endif

extension HotbarDock {
    var title: String {
        switch self {
        case .left:   "Left"
        case .bottom: "Bottom"
        case .right:  "Right"
        }
    }
}

// MARK: - Notes

private struct NotesSettings: View {
    var onExportFinished: (Int) -> Void

    @AppStorage(NewNotes.defaultsKey) private var newNotes = PageOrientation.default
    @AppStorage(NewNotes.opensAfterCreatingKey) private var opensAfterCreating = NewNotes.opensAfterCreatingByDefault
    @AppStorage(PageViewMode.defaultsKey) private var viewMode = PageViewMode.default
    @AppStorage(NoteSort.defaultsKey) private var sort = NoteSort.default

    var body: some View {
        Form {
            Section {
                Picker("New Notes", selection: $newNotes) {
                    ForEach(PageOrientation.allCases, id: \.self) { Text($0.title) }
                }
                Toggle("Open Note After Creating", isOn: $opensAfterCreating)
            } footer: {
                Text("Which way up the + button's tap makes a note's pages. Hold + to choose the other for one note. A note keeps its orientation once it's made. With Open Note After Creating off, a new note is added to the list and a message offers to open it.")
            }

            DefaultPaperSection()

            Section {
                Picker("View", selection: $viewMode) {
                    ForEach(PageViewMode.allCases, id: \.self) { Text($0.title) }
                }
            } footer: {
                Text("This device's default. ••• › View changes it while a note is open.")
            }

            Section {
                Picker("Sort By", selection: sortKey) {
                    ForEach(NoteSort.Key.allCases, id: \.self) { Text($0.title) }
                }
                Picker("Order", selection: $sort.ascending) {
                    Text(sort.orderTitles.descending).tag(false)
                    Text(sort.orderTitles.ascending).tag(true)
                }
            }

            Section {
                NavigationLink("Recently Deleted") {
                    RecentlyDeletedPage(showsDone: false)
                }
                .accessibilityIdentifier("settingsRecentlyDeleted")
            } footer: {
                Text("Deleted notes wait here for 30 days before they go for good.")
            }

            Section {
                NavigationLink("Export All Notes…") {
                    ExportAllView(onFinished: onExportFinished)
                }
            } footer: {
                Text("Every note as a Markdown file, in a folder for each of yours, to keep or move to another app.")
            }
        }
        .navigationTitle("Notes")
    }

    /// Picking a key picks the way round that reads naturally, as the list's
    /// own menu does: newest first for dates, A to Z for titles.
    private var sortKey: Binding<NoteSort.Key> {
        Binding {
            sort.key
        } set: { key in
            if key != sort.key { sort = sort.with(key: key) }
        }
    }
}

// MARK: - Writing

private struct WritingSettings: View {
    @AppStorage(ShowMarkdown.defaultsKey) private var showMarkdown = ShowMarkdown.whileEditing
    @AppStorage(TextRewritingPolicy.proseDefaultsKey)
    private var rewritesProse = TextRewritingPolicy.proseEnabledByDefault
    @AppStorage(MarkerDimming.headingsKey) private var headingMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.bulletsKey) private var bulletMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.checkboxesKey) private var checkboxMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.fencesKey) private var fenceMarkers = MarkerLevel.dim

    var body: some View {
        Form {
            Section {
                Picker("Show Markdown", selection: $showMarkdown) {
                    ForEach(ShowMarkdown.allCases, id: \.self) { Text($0.title) }
                }
            } footer: {
                Text("Hashes and backticks show only on the heading or code block you're editing; Always shows them everywhere. Bold, italic, code and link marks stay hidden either way, and the toolbar shows which are on.")
            }

            Section {
                Toggle("Autocorrect", isOn: $rewritesProse)
            } footer: {
                Text("Autocorrect, automatic capitals, smart quotes and dashes and inline predictions while you type text. Turn it off to type exactly what you press. Always off inside code, whichever way this is set.")
            }

            Section {
                markerPicker("Heading Marks", selection: $headingMarkers)
                markerPicker("List Bullets", selection: $bulletMarkers)
                markerPicker("Checkboxes", selection: $checkboxMarkers)
                markerPicker("Code Fences", selection: $fenceMarkers)
            } header: {
                Text("Markers")
            } footer: {
                Text("How the marks that stay visible look: Dim is the quiet grey they have always had, Full is the text's own colour, and Off hides them without moving any line. Heading marks are the hashes shown beside the heading you're editing; List Bullets covers numbers too; a ticked checkbox always shows. These are for this device.")
            }
        }
        .navigationTitle("Writing")
    }
}

extension WritingSettings {
    fileprivate func markerPicker(_ title: String, selection: Binding<MarkerLevel>) -> some View {
        Picker(title, selection: selection) {
            ForEach(MarkerLevel.allCases, id: \.self) { Text($0.title) }
        }
    }
}

// MARK: - Code

private struct CodeSettings: View {
    @AppStorage(RunDestinationPreference.appDefaultKey)
    private var appDefault: String = CodeDestination.default.id

    @AppStorage(CodeKeys.enabledKey) private var codeKeys = CodeKeys.enabledByDefault
    @AppStorage(CodeIndent.widthKey) private var indentWidth = CodeIndent.defaultWidth
    @AppStorage(LineNumbers.defaultsKey) private var lineNumbers = LineNumbers.enabledByDefault

    @State private var isNamingCustomSite = false

    var body: some View {
        Form {
            Section {
                Picker("Run Code In", selection: $appDefault) {
                    ForEach(destinations) { Text($0.name).tag($0.id) }
                }
                Button("Another Site…") { isNamingCustomSite = true }
            } footer: {
                Text("Where new notes' code runs. A folder or a note can choose its own. Compiler Explorer can't run Java or JavaScript, so those go to a site that can. SQL has no free place to run, so it keeps Copy.")
            }

            Section {
                Toggle("Code Keys", isOn: $codeKeys)
                // The picker shows whatever is stored, so a value it can't
                // have made is read as 4 here as it is by the editor.
                Picker("Indent Width", selection: Binding(
                    get: { CodeIndent.validWidth(indentWidth) },
                    set: { indentWidth = $0 }
                )) {
                    ForEach(CodeIndent.widths, id: \.self) { Text("\($0) Spaces").tag($0) }
                }
            } footer: {
                Text("Code Keys adds a row of brackets, punctuation, indent and arrow keys above the keyboard while you type code. It isn't shown with a hardware keyboard. Return keeps a line's indent, and goes a level deeper after { ( [ or a Python colon.")
            }

            Section {
                Toggle("Line Numbers", isOn: $lineNumbers)
            } footer: {
                Text("Numbers each line of a code block in the page's margin. They print too, and turning them on moves nothing on the page.")
            }
        }
        .navigationTitle("Code")
        .runDestinationSiteAlert(
            isPresented: $isNamingCustomSite,
            pageSetting: Binding {
                appDefault
            } set: { chosen in
                if let chosen { appDefault = chosen }
            }
        )
    }

    /// The built-in sites, and the custom one in use, so choosing something
    /// else doesn't make it vanish from the list.
    private var destinations: [CodeDestination] {
        var list = CodeDestination.builtIns
        let current = RunDestinationPreference.resolve([appDefault])
        if case .custom = current { list.append(current) }
        return list
    }
}

// MARK: - Help and About

private struct AboutSettings: View {
    var onOpenWelcomeNote: () -> Void
    var onShowWelcomeScreen: () -> Void

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    NoteCodeMark()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 84 * 0.2237, style: .continuous))
                        .accessibilityHidden(true)
                    Text("NoteCode")
                        .font(.title.bold())
                        .tracking(-0.03 * 28)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                // A new note each time it's asked for; the first launch's
                // copy, if it's still there, is left alone.
                Button("Welcome Note", action: onOpenWelcomeNote)
                    .accessibilityIdentifier("welcomeNoteButton")
                // The title screen of a first launch, shown again.
                Button("Welcome Screen", action: onShowWelcomeScreen)
                    .accessibilityIdentifier("welcomeScreenButton")
                if let feedback = AppInfo.feedbackURL() {
                    Link("Send Feedback", destination: feedback)
                }
                if let policy = AppInfo.privacyPolicy {
                    Link("Privacy Policy", destination: policy)
                }
                NavigationLink("Acknowledgements") { AcknowledgementsPage() }
                LabeledContent("Version", value: AppInfo.versionString())
            }
        }
        .navigationTitle("Help and About")
    }
}

private struct AcknowledgementsPage: View {
    var body: some View {
        ScrollView {
            Text(AppInfo.acknowledgements() ?? "The licence text could not be loaded.")
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Acknowledgements")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

/// The mark as an empty state's picture, in the place of an SF Symbol: the
/// default icon's mark at 64pt, hidden from VoiceOver since the title says it.
struct EmptyStateMark: View {
    var body: some View {
        NoteCodeMark()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 64 * 0.2237, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// An icon's mark, drawn on the design's 120 by 120 grid: two brackets and a
/// tilted pencil. The same geometry the app icons are made from
/// (`scripts/make-icons.swift`), in the icon's own colours: the Default's
/// white and orange on near-black unless told otherwise. It is the picture
/// of each icon in Settings, since an app icon set can't be loaded as an
/// image by name.
struct NoteCodeMark: View {
    var icon: AppIconChoice = .standard

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 120
            context.scaleBy(x: scale, y: scale)

            context.fill(Path(CGRect(x: 0, y: 0, width: 120, height: 120)), with: .color(Color(hex: icon.background)))

            var brackets = Path()
            brackets.move(to: CGPoint(x: 38, y: 38))
            brackets.addLine(to: CGPoint(x: 18, y: 60))
            brackets.addLine(to: CGPoint(x: 38, y: 82))
            brackets.move(to: CGPoint(x: 82, y: 38))
            brackets.addLine(to: CGPoint(x: 102, y: 60))
            brackets.addLine(to: CGPoint(x: 82, y: 82))
            context.stroke(brackets, with: .color(Color(hex: icon.brackets)), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))

            var pencil = Path(roundedRect: CGRect(x: 55, y: 38, width: 10, height: 36), cornerRadius: 2)
            pencil.move(to: CGPoint(x: 55, y: 77))
            pencil.addLine(to: CGPoint(x: 65, y: 77))
            pencil.addLine(to: CGPoint(x: 60, y: 89))
            pencil.closeSubpath()

            var tilted = context
            tilted.translateBy(x: -1, y: 0)
            tilted.translateBy(x: 60, y: 60)
            tilted.rotate(by: .degrees(18))
            tilted.translateBy(x: -60, y: -60)
            tilted.fill(pencil, with: .color(Color(hex: icon.pencil)))
            tilted.stroke(pencil, with: .color(Color(hex: icon.pencil)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
    }
}
