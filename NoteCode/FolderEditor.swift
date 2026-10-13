//
//  FolderEditor.swift
//  NoteCode
//
//  The sheet for making a folder or changing one: its name, colour and symbol.
//

import SwiftData
import SwiftUI

/// What the folder editor is for.
enum FolderEditing: Identifiable {
    /// A new folder, with the note to move into it when the sheet came from a
    /// note's "Move to Folder" menu.
    case new(moving: Page?)
    case rename(Folder)

    var id: String {
        switch self {
        case .new:                 "new"
        case .rename(let folder):  "rename-\(folder.persistentModelID.hashValue)"
        }
    }

    var title: String {
        switch self {
        case .new:    "New Folder"
        case .rename: "Rename Folder"
        }
    }

    var confirmation: String {
        switch self {
        case .new:    "Create"
        case .rename: "Save"
        }
    }

    var folder: Folder? {
        if case .rename(let folder) = self { folder } else { nil }
    }

    var movingPage: Page? {
        if case .new(let page) = self { page } else { nil }
    }
}

/// What the editor holds while it is open: the three things a folder's face
/// is made of, kept together so they are applied together.
///
/// Pure, so the rules — a blank name gets a name, a new folder takes the note
/// it was made for — are tested without a sheet.
struct FolderDraft: Equatable {
    var name: String
    var color: FolderColor
    var symbol: String

    /// A new folder starts blank, in the default colour and symbol; renaming
    /// starts from the folder's own.
    init(editing folder: Folder? = nil) {
        name = folder?.name ?? ""
        color = folder?.color ?? .default
        symbol = folder?.symbol ?? FolderSymbol.default
    }

    /// Writes the draft: onto `folder` if there is one, else into a new folder
    /// in `context`, which takes `page` if given. The name is trimmed and never
    /// blank, as `Folder.name(fromTyped:)` has it.
    @discardableResult
    func apply(to folder: Folder?, moving page: Page? = nil, in context: ModelContext) -> Folder {
        let target = folder ?? Folder(name: "")
        target.name = Folder.name(fromTyped: name)
        target.colorName = color.rawValue
        target.symbolName = symbol
        if folder == nil {
            context.insert(target)
            // After the insert, as everywhere a relationship is set on a note
            // or folder the context has only just been given.
            page?.folder = target
        }
        return target
    }
}

/// The editor: a preview of the folder's face over the name, then the eight
/// colours and the sixteen symbols.
struct FolderEditor: View {
    let editing: FolderEditing

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft: FolderDraft
    @FocusState private var nameIsFocused: Bool

    init(editing: FolderEditing) {
        self.editing = editing
        _draft = State(initialValue: FolderDraft(editing: editing.folder))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        FolderBadge(color: draft.color, symbol: draft.symbol, diameter: 64)
                            .accessibilityHidden(false)
                            .accessibilityLabel("\(draft.color.title) folder, \(FolderSymbol.title(of: draft.symbol))")
                        TextField("Name", text: $draft.name)
                            .multilineTextAlignment(.center)
                            .focused($nameIsFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                            .accessibilityIdentifier("folderName")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }

                Section("Colour") {
                    HStack {
                        ForEach(FolderColor.allCases) { color in
                            swatch(color)
                            if color != FolderColor.allCases.last { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(FolderSymbol.all, id: \.self) { symbol in
                            symbolCell(symbol)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(editing.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing.confirmation, action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("folderEditorConfirm")
                }
            }
        }
        .presentationSizing(.form)
        .onAppear {
            // A new folder is named first; renaming leaves the keyboard down
            // so the colours and symbols are in view.
            if editing.folder == nil { nameIsFocused = true }
        }
    }

    private func swatch(_ color: FolderColor) -> some View {
        let isSelected = draft.color == color
        return Button {
            draft.color = color
        } label: {
            Circle()
                .fill(Color(hex: color.base))
                .frame(width: 30, height: 30)
                // A gap of the sheet's own colour, then a ring: the selected
                // swatch is the one outlined.
                .padding(3)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color(hex: color.base), lineWidth: 2)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func symbolCell(_ symbol: String) -> some View {
        let isSelected = draft.symbol == symbol
        let isDark = colorScheme == .dark
        return Button {
            draft.symbol = symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isSelected ? Color(hex: draft.color.symbol(isDark: isDark)) : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    isSelected
                        ? Color(hex: draft.color.tint(isDark: isDark))
                        : Color.secondary.opacity(0.12),
                    in: .rect(cornerRadius: 12)
                )
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FolderSymbol.title(of: symbol))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        withAnimation {
            draft.apply(to: editing.folder, moving: editing.movingPage, in: modelContext)
        }
        dismiss()
    }
}
