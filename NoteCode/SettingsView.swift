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

// MARK: - Opening it

private extension FocusedValues {
    /// Whether the window in front is showing Settings, so ⌘, can open it.
    @Entry var showsSettings: Binding<Bool>?
}

extension View {
    /// Presents Settings as a form sheet, and lets ⌘, open it.
    func settingsSheet(isPresented: Binding<Bool>) -> some View {
        self
            .focusedSceneValue(\.showsSettings, isPresented)
            .sheet(isPresented: isPresented) {
                SettingsView()
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
                    AboutSettings()
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
    @AppStorage(PageViewMode.defaultsKey) private var viewMode = PageViewMode.default
    @AppStorage(NoteSort.defaultsKey) private var sort = NoteSort.default

    var body: some View {
        Form {
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

/// The Default icon's mark, drawn on the design's 120 by 120 grid: two
/// brackets and a tilted pencil, white and orange on near-black. The same
/// geometry the app icon is made from.
struct NoteCodeMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 120
            context.scaleBy(x: scale, y: scale)

            context.fill(Path(CGRect(x: 0, y: 0, width: 120, height: 120)), with: .color(Self.background))

            var brackets = Path()
            brackets.move(to: CGPoint(x: 38, y: 38))
            brackets.addLine(to: CGPoint(x: 18, y: 60))
            brackets.addLine(to: CGPoint(x: 38, y: 82))
            brackets.move(to: CGPoint(x: 82, y: 38))
            brackets.addLine(to: CGPoint(x: 102, y: 60))
            brackets.addLine(to: CGPoint(x: 82, y: 82))
            context.stroke(brackets, with: .color(.white), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))

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
            tilted.fill(pencil, with: .color(Self.accent))
            tilted.stroke(pencil, with: .color(Self.accent), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
    }

    private static let background = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x16 / 255)
    private static let accent = Color(red: 0xFA / 255, green: 0x85 / 255, blue: 0)
}
