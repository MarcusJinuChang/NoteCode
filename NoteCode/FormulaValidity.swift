//
//  FormulaValidity.swift
//  NoteCode
//
//  LaTeX, step 2 (docs/design/latex.md › Parsing): whether a formula's TeX is
//  drawable, asked once. The styler (dimming) and `MarkdownLayout` (swapping)
//  both ask here, so they cannot disagree. A formula that is not valid is
//  never swapped; its source shows dimmed.
//
//  The question is `MTMathListBuilder.build(fromString:error:)`, which is
//  Foundation-only. Measured in the spike: unbalanced braces, unknown commands
//  and unknown environments fail there with a message, and typesetting never
//  failed after a parse. The TeX goes through `TeXAliases` first.
//

import Foundation
import SwiftMath

nonisolated enum FormulaValidity: Equatable, Sendable {
    /// Drawable; `tex` is what to hand the typesetter (aliases resolved).
    case valid(tex: String)
    /// Not drawable, with SwiftMath's message.
    case invalid(message: String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    /// The TeX to typeset, or nil when the formula is invalid.
    var tex: String? {
        if case .valid(let tex) = self { return tex }
        return nil
    }

    /// The answer for `source`, the TeX between the dollars. Cached by the
    /// source, so a note of two hundred formulas asks SwiftMath once each
    /// however often it is laid out or styled.
    static func check(_ source: String) -> FormulaValidity {
        if let cached = cache.value(for: source) { return cached }
        let answer = compute(source)
        cache.set(answer, for: source)
        return answer
    }

    /// Uncached; what `check` caches.
    static func compute(_ source: String) -> FormulaValidity {
        // An empty formula draws nothing, and a blank one would swap the
        // source for a zero-width gap the reader couldn't tap.
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalid(message: "Empty formula")
        }
        let tex = TeXAliases.resolve(source)
        var error: NSError?
        let list = MTMathListBuilder.build(fromString: tex, error: &error)
        if let error {
            return .invalid(message: error.localizedDescription)
        }
        guard list != nil else { return .invalid(message: "Could not read the formula") }
        return .valid(tex: tex)
    }

    // MARK: Cache

    /// Bounded, so a long session of typing doesn't grow it for ever: past the
    /// limit it starts over (every answer is cheap to recompute).
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [String: FormulaValidity] = [:]
        private let limit = 2_000

        func value(for key: String) -> FormulaValidity? {
            lock.lock(); defer { lock.unlock() }
            return answers[key]
        }

        func set(_ value: FormulaValidity, for key: String) {
            lock.lock(); defer { lock.unlock() }
            if answers.count >= limit { answers.removeAll(keepingCapacity: true) }
            answers[key] = value
        }

        func clear() {
            lock.lock(); defer { lock.unlock() }
            answers.removeAll()
        }
    }

    private static let cache = Cache()

    /// For tests.
    static func clearCache() { cache.clear() }
}
