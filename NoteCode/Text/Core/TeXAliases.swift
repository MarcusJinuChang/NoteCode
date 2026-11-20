//
//  TeXAliases.swift
//  NoteCode
//
//  LaTeX, step 2 (docs/design/latex.md › "What SwiftMath can't draw"): the
//  common commands SwiftMath fails to parse, rewritten to ones it draws.
//  Pure and Foundation-only, so it compiles without the package. The note's
//  text is never changed; only what is handed to the typesetter is.
//

import Foundation

nonisolated enum TeXAliases {

    /// `tex` with every alias replaced by what SwiftMath can draw. Anything
    /// not in the table passes through, so the result is no worse than the
    /// input: a formula that failed before still fails, and says so.
    static func resolve(_ tex: String) -> String {
        guard tex.contains("\\") else { return tex }
        let chars = Array(tex)
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard c == "\\", i + 1 < chars.count else {
                out.append(c)
                i += 1
                continue
            }
            let next = chars[i + 1]
            guard next.isASCII, next.isLetter else {
                // `\\`, `\{`, `\$`, `\,`: a two-character symbol, copied whole
                // so the backslash of `\\dfrac` is not read as a command's.
                out.append(c)
                out.append(next)
                i += 2
                continue
            }
            var end = i + 1
            while end < chars.count, chars[end].isASCII, chars[end].isLetter { end += 1 }
            let name = String(chars[(i + 1)..<end])
            i = end
            switch name {
            case "dfrac", "tfrac":
                out += "\\frac"
            case "implies":
                out += "\\Rightarrow "
            case "impliedby":
                out += "\\Leftarrow "
            case "varnothing":
                out += "\\emptyset "
            case "bmod":
                out += "\\mathrm{\\ mod\\ }"
            case "pmod":
                // `\pmod{n}` is "(mod n)", set off from what precedes it.
                if let (argument, after) = braceArgument(chars, from: i) {
                    out += "\\ \\left(\\mathrm{mod}\\ \(resolve(argument))\\right)"
                    i = after
                } else {
                    out += "\\pmod"
                }
            case "operatorname":
                // `\operatorname*` is left alone: its limits can't be drawn.
                if i < chars.count, chars[i] == "*" {
                    out += "\\operatorname"
                } else if let (argument, after) = braceArgument(chars, from: i) {
                    out += "\\mathrm{\(resolve(argument))}"
                    i = after
                } else {
                    out += "\\operatorname"
                }
            case "begin", "end":
                if let (argument, after) = braceArgument(chars, from: i),
                   argument == "align" || argument == "align*" {
                    out += "\\\(name){aligned}"
                    i = after
                } else {
                    out += "\\" + name
                }
            default:
                out += "\\" + name
            }
        }
        return out
    }

    /// The `{…}` group starting exactly at `index`, braces balanced and `\{`
    /// not counted, and the index after it.
    private static func braceArgument(_ chars: [Character], from index: Int) -> (String, Int)? {
        guard index < chars.count, chars[index] == "{" else { return nil }
        var depth = 0
        var j = index
        while j < chars.count {
            switch chars[j] {
            case "\\": j += 1
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return (String(chars[(index + 1)..<j]), j + 1) }
            default: break
            }
            j += 1
        }
        return nil
    }
}
