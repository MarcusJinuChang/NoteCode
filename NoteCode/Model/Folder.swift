//
//  Folder.swift
//  NoteCode
//

import Foundation
import SwiftData

extension NoteSchemaV1 {

    /// A group of notes in the list, such as one class's.
    ///
    /// A note is in one folder or none (`Page.folder`). Folders nest (16 Oct):
    /// a folder is in another folder or at the top (`parent`), as many levels
    /// down as the reader likes, and the reader arranges the folders at each
    /// level by hand (`sortIndex`). Where a folder or note may go is
    /// `ListDrop`'s business, and the rule that keeps a folder out of its own
    /// subtree is `canMove(into:)`.
    @Model
    final class Folder {
        var name: String = ""
        var createdAt: Date = Date.now

        /// Whether the folder is pinned to the top of the list.
        var isPinned: Bool = false

        /// Unused since 30 Oct, like `Page.runDestination`: kept so version
        /// 1's hashes stay as they are.
        var runDestination: String?

        /// The folder's colour — a `FolderColor` raw value — or `nil`, which
        /// is orange. A name rather than a colour, so the same folder is the
        /// light tint in light and the dark tint in dark.
        var colorName: String?

        /// The folder's symbol, an SF Symbol name from `FolderSymbol.all`, or
        /// `nil`, which is `folder`.
        var symbolName: String?

        /// When the folder was moved to Recently Deleted, or `nil` for a folder
        /// that is where the reader left it. Set only by deleting a folder
        /// **with its notes**, which stamps every note it moves with the same date,
        /// so restoring the folder knows which notes went with it
        /// (`Page.isDeletedWithFolder`). Deleting a folder and keeping its notes
        /// removes it for good: there is nothing in it to bring back.
        var deletedAt: Date?

        /// The folder this one is in, or `nil` for a folder at the top of the list.
        var parent: Folder?

        /// The folders in this one. Deleting a folder moves its subfolders to
        /// its own parent (`Folder.delete`), so the nullify rule never has to.
        /// Optional because CloudKit requires it of every relationship.
        @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
        var subfolders: [Folder]? = []

        /// Where the folder sits among the folders with the same parent: the
        /// reader's order, set whenever a folder is dragged (`Folder.move`).
        /// `Int.max` is "never arranged", which sorts after every arranged
        /// folder, by name, so a new folder lands at the end of its level.
        var sortIndex: Int = Int.max

        /// The notes filed here, in no particular order.
        ///
        /// Deleting a folder leaves its notes, in its parent (or the top of the list), unless
        /// they're deleted with it on purpose (`Folder.delete`). Notes in
        /// Recently Deleted are in here too; ask `livePages` for the ones the
        /// reader sees. Optional because CloudKit requires it of every
        /// relationship.
        @Relationship(deleteRule: .nullify, inverse: \Page.folder)
        var pages: [Page]? = []

        init(name: String, createdAt: Date = .now) {
            self.name = name
            self.createdAt = createdAt
        }
    }
}
