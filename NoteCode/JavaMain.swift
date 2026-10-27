//
//  JavaMain.swift
//  NoteCode
//
//  Judge0 compiles Java as Main.java and runs `Main`, so a program whose
//  `public class Solution` holds `main` has to be sent as `Main`.
//

import Foundation

nonisolated enum JavaMain {
    /// The code to send and, when a rename happened, the class's old name.
    /// Left alone (nil) when `Main` already holds `main`, when no class is
    /// found holding it, or when a different class is already called `Main`
    /// (renaming would clash; the compiler's message is the better answer).
    static func prepare(_ code: String) -> (code: String, renamed: String?) {
        let units = Array(code.utf16)
        let live = liveMask(units)
        guard let owner = classHoldingMain(units, live: live), owner != "Main" else {
            return (code, nil)
        }
        if wordOccurrences(of: "Main", in: units, live: live) .isEmpty == false {
            return (code, nil)
        }
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var last = 0
        for r in wordOccurrences(of: owner, in: units, live: live) {
            out.append(contentsOf: units[last..<r.lowerBound])
            out.append(contentsOf: "Main".utf16)
            last = r.upperBound
        }
        out.append(contentsOf: units[last...])
        return (String(decoding: out, as: UTF16.self), owner)
    }

    // MARK: Scanning

    /// For each UTF-16 unit, whether it is code: false inside comments,
    /// string and character literals and text blocks.
    static func liveMask(_ u: [UInt16]) -> [Bool] {
        var live = [Bool](repeating: true, count: u.count)
        let slash = ascii("/"), star = ascii("*")
        let quote = ascii("\""), apos = ascii("'")
        let back = ascii("\\"), nl = ascii("\n")
        var i = 0
        func at(_ k: Int) -> UInt16 { k < u.count ? u[k] : 0 }
        while i < u.count {
            let c = u[i]
            if c == slash && at(i + 1) == slash {
                while i < u.count && u[i] != nl { live[i] = false; i += 1 }
            } else if c == slash && at(i + 1) == star {
                live[i] = false; live[i + 1 < u.count ? i + 1 : i] = false
                i += 2
                while i < u.count && !(u[i] == star && at(i + 1) == slash) { live[i] = false; i += 1 }
                for k in i..<min(i + 2, u.count) { live[k] = false }
                i += 2
            } else if c == quote && at(i + 1) == quote && at(i + 2) == quote {
                for k in i..<i + 3 { live[k] = false }
                i += 3
                while i < u.count {
                    if u[i] == back { live[i] = false; if i + 1 < u.count { live[i + 1] = false }; i += 2; continue }
                    if u[i] == quote && at(i + 1) == quote && at(i + 2) == quote { break }
                    live[i] = false; i += 1
                }
                for k in i..<min(i + 3, u.count) { live[k] = false }
                i += 3
            } else if c == quote || c == apos {
                live[i] = false
                i += 1
                while i < u.count && u[i] != c && u[i] != nl {
                    if u[i] == back { live[i] = false; i += 1 }
                    if i < u.count { live[i] = false; i += 1 }
                }
                if i < u.count { live[i] = false }
                i += 1
            } else {
                i += 1
            }
        }
        return live
    }

    private static func isIdent(_ c: UInt16) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127
    }

    /// Whole-word matches of `word` in live code, as unit ranges.
    static func wordOccurrences(of word: String, in u: [UInt16], live: [Bool]) -> [Range<Int>] {
        let w = Array(word.utf16)
        guard !w.isEmpty, u.count >= w.count else { return [] }
        var found: [Range<Int>] = []
        var i = 0
        while i <= u.count - w.count {
            if live[i], u[i] == w[0], Array(u[i..<i + w.count]) == w,
               !live[i..<i + w.count].contains(false),
               i == 0 || !isIdent(u[i - 1]),
               i + w.count == u.count || !isIdent(u[i + w.count]) {
                found.append(i..<i + w.count)
                i += w.count
            } else {
                i += 1
            }
        }
        return found
    }

    /// The innermost class whose body holds `main(String…)`.
    private static func classHoldingMain(_ u: [UInt16], live: [Bool]) -> String? {
        let mains = wordOccurrences(of: "main", in: u, live: live).filter { r in
            var k = r.upperBound
            while k < u.count, u[k] == 32 || u[k] == 9 || u[k] == 10 || u[k] == 13 { k += 1 }
            guard k < u.count, u[k] == ascii("(") else { return false }
            k += 1
            while k < u.count, u[k] == 32 || u[k] == 9 || u[k] == 10 || u[k] == 13 { k += 1 }
            let rest = String(decoding: u[k..<min(k + 12, u.count)], as: UTF16.self)
            return rest.hasPrefix("String") || rest.hasPrefix("final")
        }
        guard let main = mains.first else { return nil }
        let classes = wordOccurrences(of: "class", in: u, live: live)
        var classAt: [Int: String] = [:]   // index of the keyword's end -> name
        for r in classes {
            var k = r.upperBound
            while k < u.count, u[k] == 32 || u[k] == 9 || u[k] == 10 || u[k] == 13 { k += 1 }
            let start = k
            while k < u.count, isIdent(u[k]) { k += 1 }
            if k > start { classAt[r.upperBound] = String(decoding: u[start..<k], as: UTF16.self) }
        }
        var stack: [String?] = []
        var pending: String?
        var i = 0
        while i < main.lowerBound {
            if live[i] {
                if u[i] == ascii("{") { stack.append(pending); pending = nil }
                else if u[i] == ascii("}") { if !stack.isEmpty { stack.removeLast() } }
                else if let name = classAt[i] { pending = name }
            }
            i += 1
        }
        return stack.last(where: { $0 != nil }) ?? nil
    }
}

private nonisolated func ascii(_ s: Unicode.Scalar) -> UInt16 { UInt16(s.value) }
