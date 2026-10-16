//
//  NoteListDrop.swift
//  NoteCode
//
//  Dragging in the note list: what dropping a note or a folder on a row does.
//  Pure rules, so every case is tested without a drag.
//

import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What is being dragged.
enum ListDragItem {
    case note(Page)
    case folder(Folder)
}

/// Where on a row a drop lands. The top and bottom edges are "before" and
/// "after" the row, to arrange folders; the middle is "into" it.
enum DropZone: Equatable {
    case before, into, after

    /// The share of a row's height at its top and at its bottom that arranges
    /// rather than files.
    static let edge: CGFloat = 0.28

    /// The zone at `y` down a row `height` tall.
    static func zone(atY y: CGFloat, height: CGFloat) -> DropZone {
        guard height > 0 else { return .into }
        let fraction = y / height
        if fraction < edge { return .before }
        if fraction > 1 - edge { return .after }
        return .into
    }
}

/// What a drop can land on.
enum ListDropTarget {
    case folder(Folder)
    case note(Page)
    /// The "Folders" header: the top level of folders.
    case topFolders
    /// The "Notes" header: notes in no folder.
    case topNotes
}

/// What a drop does.
enum ListDropAction: Equatable {
    /// File the note in a folder, or take it out of its folder (`nil`).
    case fileNote(Page, into: Folder?)
    /// Put the folder inside another (or at the top, `nil`), at `index` among
    /// the folders already there (the end when `nil`).
    case moveFolder(Folder, into: Folder?, at: Int?)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.fileNote(a, b), .fileNote(c, d)): a === c && b === d
        case let (.moveFolder(a, b, i), .moveFolder(c, d, j)): a === c && b === d && i == j
        default: false
        }
    }
}

enum ListDrop {

    /// The type a drag carries. Own-process only, so a note or folder can't be
    /// dropped on another app, and nothing else is taken as one.
    static let type = UTType(exportedAs: "com.marcus.NoteCode.list-item")

    /// What dropping `item` on `target`, at `zone`, does: `nil` when it does
    /// nothing, or isn't allowed (a folder into itself or its own subtree).
    ///
    /// - Parameter folders: every folder, to find where among its new
    ///   neighbours a folder lands.
    static func resolve(
        _ item: ListDragItem,
        onto target: ListDropTarget,
        zone: DropZone,
        among folders: [Folder]
    ) -> ListDropAction? {
        switch (item, target) {

        // Notes are filed, never arranged: into a folder, beside a note (the
        // same folder as it), or out to the top.
        case let (.note(page), .folder(folder)):
            return page.folder === folder ? nil : .fileNote(page, into: folder)
        case let (.note(page), .note(other)):
            return page === other || page.folder === other.folder ? nil : .fileNote(page, into: other.folder)
        case let (.note(page), .topNotes), let (.note(page), .topFolders):
            return page.folder == nil ? nil : .fileNote(page, into: nil)

        case let (.folder(folder), .folder(other)):
            guard folder !== other else { return nil }
            // A pinned folder is listed apart from its neighbours, so there is
            // no before or after it: only into.
            let zone = other.isPinned ? DropZone.into : zone
            switch zone {
            case .into:
                return folder.canMove(into: other) ? .moveFolder(folder, into: other, at: nil) : nil
            case .before, .after:
                let parent = other.parent
                guard folder.canMove(into: parent) else { return nil }
                let siblings = Folder.children(of: parent, in: folders).filter { $0 !== folder }
                guard let position = siblings.firstIndex(where: { $0 === other }) else { return nil }
                return .moveFolder(folder, into: parent, at: zone == .before ? position : position + 1)
            }
        case (.folder(let folder), .topFolders):
            return .moveFolder(folder, into: nil, at: nil)

        case (.folder, .note), (.folder, .topNotes):
            return nil
        }
    }

    /// Does it. Moving a note isn't an edit and keeps its date, like every
    /// move; the change is saved by autosave.
    static func perform(_ action: ListDropAction, among folders: [Folder]) {
        switch action {
        case let .fileNote(page, folder):
            page.folder = folder
        case let .moveFolder(folder, parent, index):
            Folder.move(folder, into: parent, at: index, among: folders)
        }
    }

    // MARK: Payload

    /// The bytes a drag carries: only what tells it from a drag of something
    /// else. Which note or folder it is stays with the list, which knows what
    /// it lifted.
    static let payload = Data("notecode-list-item".utf8)
}

// MARK: - In the list

/// What the list is dragging and where it would land: one per list.
///
/// The row lifted is kept here, since a drag carries only a marker
/// (`ListDrop.payload`), and the row under the finger is `hover`, which draws
/// its drop indicator.
@MainActor
@Observable
final class ListDragState {
    enum HoverID: Hashable {
        case row(NoteListRow.ID)
        case topFolders
        case topNotes
    }

    struct Hover: Equatable {
        var id: HoverID
        var zone: DropZone
    }

    @ObservationIgnored var item: ListDragItem?
    var hover: Hover?

    /// Begins a drag of `item`: the provider the list hands to the system.
    /// Own-process only, so it can't be dropped in another app.
    func lift(_ item: ListDragItem) -> NSItemProvider {
        self.item = item
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: ListDrop.type.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(ListDrop.payload, nil)
            return nil
        }
        return provider
    }
}

/// Makes a row a drop target: shows where the drop would land and does it.
///
/// Zones come from where on the row the finger is (`DropZone`), read against
/// the row's own height, which a modifier can keep as state.
struct ListRowDrop: ViewModifier {
    let target: ListDropTarget
    let hoverID: ListDragState.HoverID
    let drag: ListDragState
    let folders: [Folder]
    let perform: (ListDropAction) -> Void

    @State private var height: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
            .overlay { indicator }
            .onDrop(of: [ListDrop.type], delegate: Delegate(
                target: target, hoverID: hoverID, drag: drag, folders: folders,
                height: height, perform: perform
            ))
    }

    @ViewBuilder
    private var indicator: some View {
        if let hover = drag.hover, hover.id == hoverID {
            Group {
                switch hover.zone {
                case .into:
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2)
                case .before:
                    Rectangle().fill(.tint).frame(height: 3)
                        .frame(maxHeight: .infinity, alignment: .top)
                case .after:
                    Rectangle().fill(.tint).frame(height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .allowsHitTesting(false)
        }
    }

    struct Delegate: DropDelegate {
        let target: ListDropTarget
        let hoverID: ListDragState.HoverID
        let drag: ListDragState
        let folders: [Folder]
        let height: CGFloat
        let perform: (ListDropAction) -> Void

        private func zone(_ info: DropInfo) -> DropZone {
            DropZone.zone(atY: info.location.y, height: height)
        }

        private func action(_ info: DropInfo) -> ListDropAction? {
            guard info.hasItemsConforming(to: [ListDrop.type]), let item = drag.item else { return nil }
            return ListDrop.resolve(item, onto: target, zone: zone(info), among: folders)
        }

        func validateDrop(info: DropInfo) -> Bool {
            action(info) != nil
        }

        func dropEntered(info: DropInfo) {
            update(info)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            update(info)
            return DropProposal(operation: action(info) == nil ? .forbidden : .move)
        }

        func dropExited(info: DropInfo) {
            if drag.hover?.id == hoverID { drag.hover = nil }
        }

        func performDrop(info: DropInfo) -> Bool {
            guard let action = action(info) else { return false }
            drag.hover = nil
            drag.item = nil
            perform(action)
            return true
        }

        private func update(_ info: DropInfo) {
            let next = action(info) == nil ? nil : ListDragState.Hover(id: hoverID, zone: zone(info))
            if drag.hover != next { drag.hover = next }
        }
    }
}
