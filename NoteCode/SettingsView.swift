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

extension View {
    /// Presents Settings as a form sheet, and lets ⌘, open it.
    ///
    /// - Parameter onOpenWelcomeNote: called when Help and About › Welcome
    ///   Note is chosen, after the sheet has been asked to close. The note is
    ///   opened by the window, which owns what's selected.
    func settingsSheet(isPresented: Binding<Bool>, onOpenWelcomeNote: @escaping () -> Void = {}) -> some View {
        self
            .focusedSceneValue(\.showsSettings, isPresented)
            .sheet(isPresented: isPresented) {
                SettingsView(onOpenWelcomeNote: onOpenWelcomeNote)
                    .presentationSizing(.form)
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
            .keyboardShortcut(",", modifiers: .command)
            .disabled(showsSettings == nil)
        }
    }
}

/// Applies Settings › General › Appearance to a window's content.
///
/// At the root of the scene, so a change reaches every window, its sheets and
/// the UIKit controllers presented from it, the moment the setting changes.
struct AppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.default

    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance.colorScheme)
    }
}

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

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    GeneralSettings()
                } label: {
                    Label("General", systemImage: "gearshape")
                }
                NavigationLink {
                    NotesSettings()
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
                    AboutSettings(onOpenWelcomeNote: {
                        dismiss()
                        onOpenWelcomeNote()
                    })
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
#if canImport(UIKit)
    @AppStorage(HotbarDock.defaultsKey) private var dock = HotbarDock.default
    @AppStorage(SnapHaptic.defaultsKey) private var hapticOnSnap = SnapHaptic.isOnByDefault
#endif

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.title) }
                }
            }
#if canImport(UIKit)
            AppIconSection()

            // The Mac has no hotbar: its editor is text only.
            Section {
                Picker("Toolbar Position", selection: $dock) {
                    ForEach(HotbarDock.allCases, id: \.self) { Text($0.title) }
                }
                Toggle("Haptic on Snap", isOn: $hapticOnSnap)
            } footer: {
                Text("Toolbar Position moves the bar without dragging it. Dragging the bar's grip to an edge does the same.")
            }
#endif
        }
        .navigationTitle("General")
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
    @AppStorage(NewNotes.defaultsKey) private var newNotes = PageOrientation.default
    @AppStorage(PageViewMode.defaultsKey) private var viewMode = PageViewMode.default
    @AppStorage(NoteSort.defaultsKey) private var sort = NoteSort.default

    var body: some View {
        Form {
            Section {
                Picker("New Notes", selection: $newNotes) {
                    ForEach(PageOrientation.allCases, id: \.self) { Text($0.title) }
                }
            } footer: {
                Text("Which way up the + button's tap makes a note's pages. Hold + to choose the other for one note. A note keeps its orientation once it's made.")
            }

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

    var body: some View {
        Form {
            Section {
                Picker("Show Markdown", selection: $showMarkdown) {
                    ForEach(ShowMarkdown.allCases, id: \.self) { Text($0.title) }
                }
            } footer: {
                Text("While Editing hides a code block's backticks when the caret is outside it. Autocorrect and smart punctuation follow the keyboard settings in the Settings app, and are off inside code.")
            }
        }
        .navigationTitle("Writing")
    }
}

// MARK: - Code

private struct CodeSettings: View {
    @AppStorage(RunDestinationPreference.appDefaultKey)
    private var appDefault: String = CodeDestination.default.id

    @State private var isNamingCustomSite = false

    var body: some View {
        Form {
            Section {
                Picker("Run Code In", selection: $appDefault) {
                    ForEach(destinations) { Text($0.name).tag($0.id) }
                }
                Button("Another Site…") { isNamingCustomSite = true }
            } footer: {
                Text("Where new notes' code runs. A folder or a note can choose its own. Compiler Explorer can't run Java, so Java goes to a site that can.")
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

private extension Color {
    /// An sRGB colour from the hex `AppIconChoice` keeps its colours in.
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
