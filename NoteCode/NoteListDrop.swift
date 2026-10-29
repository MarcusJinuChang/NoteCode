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
#if canImport(UIKit)
import UIKit
#endif

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
    /// The Recently Deleted row at the list's foot.
    case recentlyDeleted

    /// What lifting this row drags: nothing, for the headers.
    var dragItem: ListDragItem? {
        switch self {
        case .folder(let folder): .folder(folder)
        case .note(let page):     .note(page)
        case .topFolders, .topNotes, .recentlyDeleted: nil
        }
    }
}

/// What a drop does.
enum ListDropAction: Equatable {
    /// File the note in a folder, or take it out of its folder (`nil`).
    case fileNote(Page, into: Folder?)
    /// Put the folder inside another (or at the top, `nil`), at `index` among
    /// the folders already there (the end when `nil`).
    case moveFolder(Folder, into: Folder?, at: Int?)
    /// Send the note to Recently Deleted.
    case deleteNote(Page)
    /// Send the folder, its folders and its notes to Recently Deleted: what
    /// the folder menu's Delete does when its notes go too.
    case deleteFolder(Folder)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.deleteNote(a), .deleteNote(b)): a === b
        case let (.deleteFolder(a), .deleteFolder(b)): a === b
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

        // Onto Recently Deleted: a note that is already live, or a folder
        // that is.
        case let (.note(page), .recentlyDeleted):
            return page.isLive ? .deleteNote(page) : nil
        case let (.folder(folder), .recentlyDeleted):
            return folder.isLive ? .deleteFolder(folder) : nil
        }
    }

    /// Does it. Moving a note isn't an edit and keeps its date, like every
    /// move; the change is saved by autosave. Deleting saves at once, as
    /// `Page.moveToRecentlyDeleted` and `Folder.delete` do, so it needs the
    /// `context`.
    static func perform(_ action: ListDropAction, among folders: [Folder], in context: ModelContext? = nil) {
        switch action {
        case let .deleteNote(page):
            if let context { try? Page.moveToRecentlyDeleted([page], from: context) }
        case let .deleteFolder(folder):
            if let context { try? Folder.delete(folder, .withNotes, from: context) }
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

// MARK: - Where a drop lands

/// Which row a drop is over, from where the rows are on screen. Pure, so the
/// rows and their edges are tested without a drag.
enum ListDropHit {

    /// How far past a row's top and bottom still counts as that row, so the
    /// gaps between rows take a drop rather than refusing it.
    static let slack: CGFloat = 4

    /// The row at window height `y`, and where on it: `frames` are the rows'
    /// frames in the window. A row's own span wins over a neighbour's slack.
    static func row<ID: Hashable>(atY y: CGFloat, in frames: [ID: CGRect]) -> (id: ID, zone: DropZone)? {
        let inside = frames.first { $0.value.minY <= y && y < $0.value.maxY }
        let near = frames.first { $0.value.minY - slack <= y && y < $0.value.maxY + slack }
        guard let (id, frame) = inside ?? near else { return nil }
        return (id, DropZone.zone(atY: y - frame.minY, height: frame.height))
    }
}

// MARK: - In the list

/// What the list is dragging, where its rows are and where a drop would land:
/// one per list.
///
/// The row lifted is kept here, since a drag carries only a marker
/// (`ListDrop.payload`), and the row under the finger is `hover`, which draws
/// its drop indicator.
///
/// The rows' places are kept here too, because a drop is taken by the list as
/// a whole (`ListDropBridge`), not by its rows.
@MainActor
@Observable
final class ListDragState {
    enum HoverID: Hashable {
        case row(NoteListRow.ID)
        case topFolders
        case topNotes
        case recentlyDeleted
    }

    struct Hover: Equatable {
        var id: HoverID
        var zone: DropZone
    }

    @ObservationIgnored var item: ListDragItem?
    var hover: Hover?

    /// Each visible row's frame in the window, and what dropping on it means.
    /// Kept as the rows scroll; not observed, since nothing draws from it.
    @ObservationIgnored var frames: [HoverID: CGRect] = [:]
    @ObservationIgnored var targets: [HoverID: ListDropTarget] = [:]

    /// The provider the list hands to the system for a drag of `item`.
    /// Own-process only, so it can't be dropped in another app.
    ///
    /// It doesn't note what was lifted: SwiftUI asks for a row's provider when
    /// it likes, and on an iPad did so for a folder's row after a note's drag
    /// had begun (`-debug-probe`, 24 Oct), which made the drag a folder's.
    /// What was lifted is read from where the drag began (`ListDragSource`).
    func lift(_ item: ListDragItem) -> NSItemProvider {
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

/// Makes a row a drop target: records where it is, so the list's drop can find
/// it, and shows where a drop would land.
///
/// Zones come from where on the row the finger is (`DropZone`), against the
/// row's own frame.
struct ListRowDrop: ViewModifier {
    let target: ListDropTarget
    let hoverID: ListDragState.HoverID
    let drag: ListDragState
    /// How far past the view, up and down, a drop still counts as on it: for
    /// the header, whose text is smaller than the row it sits in.
    var outset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                drag.frames[hoverID] = frame.insetBy(dx: 0, dy: -outset)
                drag.targets[hoverID] = target
            }
            .onDisappear {
                drag.frames[hoverID] = nil
                drag.targets[hoverID] = nil
            }
            .overlay { indicator }
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
}

extension ListDragState {

    /// What dropping at window height `y` would do: the row under it, where on
    /// it, and what that does for what is being dragged.
    func resolution(atY y: CGFloat, among folders: [Folder]) -> (id: HoverID, zone: DropZone, action: ListDropAction)? {
        guard let item,
              let hit = ListDropHit.row(atY: y, in: frames),
              let target = targets[hit.id],
              let action = ListDrop.resolve(item, onto: target, zone: hit.zone, among: folders)
        else { return nil }
        return (hit.id, hit.zone, action)
    }
}

#if canImport(UIKit)

// MARK: - Taking the drop

private extension UIView {
    /// The first collection view in this view's subviews, or this view.
    func findCollectionView() -> UICollectionView? {
        if let collection = self as? UICollectionView { return collection }
        for sub in subviews { if let found = sub.findCollectionView() { return found } }
        return nil
    }
}

/// Takes drops for a `List` from its collection view.
///
/// A `List` is a `UICollectionView`, and SwiftUI answers its drag and drop
/// itself (`CollectionViewListDragAndDropController`): it lifts a row for
/// `.onDrag`, and has no ear for `.onDrop`, `.dropDestination`, a list-level
/// `onDrop` or `onInsert` with a custom type. Read on an iPad Pro (24 Oct,
/// `-debug-probe` over a real press and drag): the same row-level delegate on
/// a stack's row is called, on a list's row never. So the list's own drop
/// delegate is wrapped here: a drag of ours (`ListDrop.type`) is answered from
/// where the rows are, and anything else goes to SwiftUI's as before.
///
/// Laid behind the list (`.background`), which is how it finds the collection
/// view: the nearest one in the views around it.
struct ListDropBridge: UIViewRepresentable {
    let drag: ListDragState
    let folders: [Folder]
    let perform: (ListDropAction) -> Void

    func makeUIView(context: Context) -> Finder {
        let view = Finder()
        view.isUserInteractionEnabled = false
        view.bridge = context.coordinator
        return view
    }

    func updateUIView(_ view: Finder, context: Context) {
        context.coordinator.update(self)
        view.installIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// The view that goes looking for the collection view once it is on screen,
    /// and again after each update, since SwiftUI may put its own delegate back.
    final class Finder: UIView {
        var bridge: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // The list's cells aren't laid out yet at this point.
            DispatchQueue.main.async { [weak self] in self?.installIfNeeded() }
        }

        func installIfNeeded() {
            guard window != nil, let bridge else { return }
            var level: UIView = self
            while level.findCollectionView() == nil, let up = level.superview { level = up }
            if let collection = level.findCollectionView() { bridge.install(on: collection) }
        }
    }

    /// The list's drag delegate with one thing added: when a drag begins, the
    /// row at the finger is what is being dragged. Everything else is SwiftUI's.
    final class ListDragSource: NSObject, UICollectionViewDragDelegate {
        private let target: any UICollectionViewDragDelegate
        private let state: ListDragState

        init(wrapping target: any UICollectionViewDragDelegate, state: ListDragState) {
            self.target = target
            self.state = state
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || target.responds(to: selector)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? { target }

        func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            let items = target.collectionView(collectionView, itemsForBeginning: session, at: indexPath)
            guard !items.isEmpty, let window = collectionView.window else { return items }
            let y = session.location(in: window).y
            state.item = ListDropHit.row(atY: y, in: state.frames)
                .flatMap { state.targets[$0.id] }
                .flatMap(\.dragItem)
#if DEBUG
            DeviceProbe.log("drag begins at y=\(y): \(String(describing: state.item))")
#endif
            return items
        }

        func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: any UIDragSession) {
            state.item = nil
            state.hover = nil
            target.collectionView?(collectionView, dragSessionDidEnd: session)
        }
    }

    final class Coordinator: NSObject, UICollectionViewDropDelegate {
        private var current: ListDropBridge
        /// SwiftUI's own delegate, for every drag that isn't ours. Held here:
        /// a collection view's delegate is weak.
        private var swiftUI: (any UICollectionViewDropDelegate)?
        private var dragSource: ListDragSource?

        init(_ bridge: ListDropBridge) { current = bridge }

        func update(_ bridge: ListDropBridge) { current = bridge }

        func install(on collection: UICollectionView) {
            shortenLift(on: collection)
            guard collection.dropDelegate !== self else { return }
            swiftUI = collection.dropDelegate
            collection.dropDelegate = self
            if !(collection.dragDelegate is ListDragSource), let drag = collection.dragDelegate {
                dragSource = ListDragSource(wrapping: drag, state: current.drag)
                collection.dragDelegate = dragSource
            }
#if DEBUG
            DeviceProbe.log("list drop bridge on \(type(of: collection)), wrapping \(swiftUI.map { String(describing: type(of: $0)) } ?? "nothing")")
#endif
        }

        /// How long a row is held before it lifts, down from the system's
        /// 0.5s. The lift is a long press the collection view's drag
        /// interaction owns, found among its recognizers: it is a
        /// `UILongPressGestureRecognizer`, public API, and only its class
        /// (private) is looked for by name. Absent, nothing changes.
        static let liftDuration: TimeInterval = 0.25

        private func shortenLift(on collection: UICollectionView) {
            for recognizer in collection.gestureRecognizers ?? [] {
                guard let press = recognizer as? UILongPressGestureRecognizer,
                      String(describing: type(of: press)).contains("Drag"),
                      press.minimumPressDuration != Self.liftDuration else { continue }
#if DEBUG
                DeviceProbe.log("lift recogniser \(type(of: press)) held \(press.minimumPressDuration)s, now \(Self.liftDuration)s")
#endif
                press.minimumPressDuration = Self.liftDuration
            }
        }

        private func isOurs(_ session: any UIDropSession) -> Bool {
            session.hasItemsConforming(toTypeIdentifiers: [ListDrop.type.identifier])
        }

        private func resolution(_ collection: UICollectionView, _ session: any UIDropSession) -> (id: ListDragState.HoverID, zone: DropZone, action: ListDropAction)? {
            guard let window = collection.window else { return nil }
            return current.drag.resolution(atY: session.location(in: window).y, among: current.folders)
        }

        // MARK: UICollectionViewDropDelegate

        func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool {
            isOurs(session) ? current.drag.item != nil : swiftUI?.collectionView?(collectionView, canHandle: session) ?? true
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnter session: any UIDropSession) {
            if !isOurs(session) { swiftUI?.collectionView?(collectionView, dropSessionDidEnter: session) }
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
            guard isOurs(session) else {
                return swiftUI?.collectionView?(collectionView, dropSessionDidUpdate: session, withDestinationIndexPath: destinationIndexPath)
                    ?? UICollectionViewDropProposal(operation: .cancel)
            }
            let found = resolution(collectionView, session)
            let next = found.map { ListDragState.Hover(id: $0.id, zone: $0.zone) }
            if current.drag.hover != next {
                current.drag.hover = next
#if DEBUG
                DeviceProbe.log("list hover \(String(describing: next)) y=\(session.location(in: collectionView).y) item=\(String(describing: current.drag.item))")
#endif
            }
            return UICollectionViewDropProposal(operation: found == nil ? .forbidden : .move, intent: .unspecified)
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: any UIDropSession) {
            if isOurs(session) {
                current.drag.hover = nil
            } else {
                swiftUI?.collectionView?(collectionView, dropSessionDidExit: session)
            }
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: any UIDropSession) {
#if DEBUG
            DeviceProbe.log("list session ended, ours=\(isOurs(session))")
#endif
            if isOurs(session) {
                current.drag.hover = nil
            } else {
                swiftUI?.collectionView?(collectionView, dropSessionDidEnd: session)
            }
        }

        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
            guard isOurs(coordinator.session) else {
                swiftUI?.collectionView(collectionView, performDropWith: coordinator)
                return
            }
            let found = resolution(collectionView, coordinator.session)
#if DEBUG
            DeviceProbe.log("list performDrop hit=\(found != nil)")
#endif
            current.drag.hover = nil
            current.drag.item = nil
            if let found { current.perform(found.action) }
        }
    }
}

#endif
