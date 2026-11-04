//
//  GeneralSettings.swift
//  NoteCode
//
//  Settings › General (split out of SettingsView.swift).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct GeneralSettings: View {
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
    /// Each icon's picture in the list, the height of a two-line row.
    private static let iconSide: CGFloat = 44

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
                                .frame(width: Self.iconSide, height: Self.iconSide)
                                .clipShape(RoundedRectangle(cornerRadius: NoteCodeMark.cornerRadius(side: Self.iconSide), style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: NoteCodeMark.cornerRadius(side: Self.iconSide), style: .continuous)
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
