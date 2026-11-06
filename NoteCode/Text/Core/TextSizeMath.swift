//
//  TextSizeMath.swift
//  NoteCode
//
//  The size control's arithmetic: stepping, clamping, a typed size, and where an offset lands after an edit.
//


import Foundation

nonisolated enum TextSizeMath {

    /// `points` stepped a point at a time, or `nil` past the control's ends.
    /// Text already outside them (a large run in a note made larger) steps
    /// back towards them, never further out.
    nonisolated static func stepped(_ points: Double, by steps: Int) -> Double? {
        SpanSize.stepped(points, by: steps)
    }

    /// A size the control can set: 8 to 72, to the half point.
    nonisolated static func clampedPoints(_ points: Double) -> Double {
        (min(max(points, SpanSize.points.lowerBound), SpanSize.points.upperBound) * 2).rounded() / 2
    }

    /// A typed size: a number, with "pt" or without, and a comma for a
    /// decimal point as some keyboards type it.
    nonisolated static func points(typed: String) -> Double? {
        var text = typed.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix("pt") { text.removeLast(2) }
        text = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite else { return nil }
        return clampedPoints(value)
    }

    /// Where `offset` in the text before `edit` is after it, if it lies in
    /// what the edit left as it was: the start of the lines it rewrote, up
    /// to the first change, or their end, from the last. `nil` in between.
    nonisolated static func offset(_ offset: Int, through edit: TextEdit, replacing old: String) -> Int? {
        let old = Array(old.utf16)
        let new = Array(edit.replacement.utf16)
        if offset <= edit.range.location { return offset }
        if offset >= NSMaxRange(edit.range) { return offset + new.count - old.count }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let local = offset - edit.range.location
        if local <= prefix { return offset }
        if local >= old.count - suffix { return offset + new.count - old.count }
        return nil
    }
}

