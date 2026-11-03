//
//  Storage.swift
//  NoteCode
//
//  Opening the SwiftData store, and coping when it can't be opened.
//

import Foundation
import SwiftData

/// The outcome of trying to open the page store.
///
/// The template this replaced called `fatalError` when the container failed to
/// build, which turns any storage problem on a real device — a corrupted store,
/// a full disk, a migration that didn't land — into an unrecoverable launch
/// crash with nothing the user can do and nothing they can recover.
///
/// Three outcomes instead:
///
/// - `persistent`  — normal.
/// - `ephemeral`   — the on-disk store failed, but an in-memory one opened. The
///                   app runs and the user is *told* their notes won't be kept,
///                   because silently not saving is worse than crashing.
/// - `unavailable` — nothing opened. Shows an explanation rather than dying.
enum Storage {
    case persistent(ModelContainer)
    case ephemeral(ModelContainer, reason: String)
    case unavailable(reason: String)

    static func open() -> Storage {
        open(at: nil)
    }

    /// - Parameter url: where the store is, or `nil` for the app's own. Tests
    ///   pass a file of their own.
    static func open(at url: URL?) -> Storage {
        let schema = NoteSchema.current
        let disk = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            // The plan carries a store written by an earlier version of the
            // model across; see NoteSchema.swift.
            let container = try ModelContainer(
                for: schema,
                migrationPlan: NoteMigrationPlan.self,
                configurations: [disk]
            )
            return .persistent(container)
        } catch let diskError {
            do {
                let container = try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
                return .ephemeral(container, reason: diskError.localizedDescription)
            } catch {
                return .unavailable(reason: diskError.localizedDescription)
            }
        }
    }

    var container: ModelContainer? {
        switch self {
        case .persistent(let container):   container
        case .ephemeral(let container, _): container
        case .unavailable:                 nil
        }
    }

    /// True when edits will be lost on quit, so the UI can say so.
    var isEphemeral: Bool {
        if case .ephemeral = self { return true }
        return false
    }

    var reason: String? {
        switch self {
        case .persistent:                 nil
        case .ephemeral(_, let reason):   reason
        case .unavailable(let reason):    reason
        }
    }
}
