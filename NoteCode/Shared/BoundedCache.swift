//
//  BoundedCache.swift
//  NoteCode
//
//  A dictionary that can't grow for ever: past `limit` entries it starts
//  over. For answers that are cheap to compute again (marker widths,
//  typeset formulas, whether a formula parses, text colours). Locked, so
//  the ones read off the main thread can share it.
//

import Foundation

nonisolated final class BoundedCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Key: Value] = [:]
    let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    subscript(key: Key) -> Value? {
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }

    func set(_ value: Value, for key: Key) {
        lock.lock(); defer { lock.unlock() }
        if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
        entries[key] = value
    }

    /// The cached value, or `make()`'s, kept. Nil when `make` gives nil,
    /// which isn't kept.
    func value(for key: Key, make: () -> Value?) -> Value? {
        if let found = self[key] { return found }
        guard let fresh = make() else { return nil }
        set(fresh, for: key)
        return fresh
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }
}
