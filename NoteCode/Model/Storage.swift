//
//  Storage.swift
//  NoteCode
//
//  Opening the SwiftData store, and coping when it can't be opened.
//

import Foundation
import OSLog
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

// MARK: - Saving

/// Something that saves: a `ModelContext`, or a stand-in that fails, in tests.
protocol Savable {
    func save() throws
}

extension ModelContext: Savable {}

extension Storage {
    private nonisolated static let logger = Logger(subsystem: "com.marcus.NoteCode", category: "storage")

    /// The default `report` of the calls below: writes the failure to the log.
    nonisolated static func logFailure(_ reason: String, _ error: any Error) {
        logger.error("Could not \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    /// Saves `context`, and logs a failure instead of throwing it.
    ///
    /// For the places that used to say `try? context.save()`. Behaviour is the
    /// same: the change stays pending in the context, and autosave tries again.
    /// What is new is that the failure is no longer lost.
    ///
    /// - Parameter reason: what was being saved, in words that complete "Could
    ///   not ...", such as "save the open note".
    /// - Returns: whether it saved.
    @discardableResult
    static func save(
        _ context: some Savable,
        reason: String,
        report: (_ reason: String, _ error: any Error) -> Void = Storage.logFailure
    ) -> Bool {
        attempt(reason, report: report) { try context.save() }
    }

    /// Runs a change that saves (`Page.delete`, `Folder.restore` and the rest)
    /// and logs a failure instead of throwing it. See `save(_:reason:)`.
    @discardableResult
    static func attempt(
        _ reason: String,
        report: (_ reason: String, _ error: any Error) -> Void = Storage.logFailure,
        _ change: () throws -> Void
    ) -> Bool {
        do {
            try change()
            return true
        } catch {
            report(reason, error)
            return false
        }
    }
}
