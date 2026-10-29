//
//  FormulaValidityTests.swift
//  NoteCodeTests
//
//  LaTeX, step 2 (docs/design/latex.md): which TeX is drawable, over the
//  spike's measured lists ("What SwiftMath can't draw"), and the aliases that
//  rescue the common failures. Foundation only; SwiftMath answers the parse.
//

import Foundation
import Testing
@testable import NoteCode

struct FormulaValidityTests {

    /// Measured at parse in the spike, and not aliased: they must stay invalid.
    private let unsupported = [
        #"\underbrace{x}_{n}"#, #"\overbrace{x}^{n}"#, #"\xrightarrow{f}"#,
        #"\cancel{x}"#, #"\boxed{x}"#, #"\substack{a \\ b}"#, #"\overset{a}{b}"#,
        #"\tag{1}"#, #"\newcommand{\a}{b}"#, #"\not="#, #"\sideset{}{'}\sum"#,
        #"\href{u}{x}"#, #"\begin{array}{c} a \end{array}"#,
        #"\operatorname*{argmax}_x f"#,
    ]

    /// Drawn as they stand.
    private let supported = [
        #"\frac{a}{b}"#, #"\sqrt{x}"#, #"\sum_{i=0}^{n} i"#, #"\prod_{i} x_i"#,
        #"\int_0^1 x\,dx"#, #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#,
        #"\begin{bmatrix} 1 & 0 \\ 0 & 1 \end{bmatrix}"#,
        #"\begin{cases} 1 & x>0 \\ 0 & x \le 0 \end{cases}"#,
        #"\begin{aligned} a &= b \\ c &= d \end{aligned}"#,
        #"\binom{n}{k}"#, #"{n \choose k}"#, #"\mathbb{R}"#, #"\mathcal{O}(n)"#,
        #"\mathbf{x}"#, #"\mathrm{d}x"#, #"\text{if } x"#,
        #"\left( \frac{a}{b} \right)"#, #"\lceil \log_2 n \rceil"#,
        #"\lfloor x \rfloor"#, #"\overline{x}"#, #"\hat{x}"#, #"\vec{v}"#,
        #"\tilde{x}"#, #"\arg\min_x f"#, #"\max\limits_x f"#,
        #"\displaystyle \sum x"#, #"a \ldots b"#, #"a \cdots b"#, #"\vdots"#,
        #"\color{red}{x}"#,
    ]

    @Test func supportedFormulasAreValid() {
        for tex in supported {
            let answer = FormulaValidity.compute(tex)
            #expect(answer.isValid, "\(tex) should be drawable: \(answer)")
        }
    }

    @Test func unsupportedFormulasStayInvalidWithAMessage() {
        for tex in unsupported {
            guard case .invalid(let message) = FormulaValidity.compute(tex) else {
                Issue.record("\(tex) should not be drawable")
                continue
            }
            #expect(!message.isEmpty)
        }
    }

    @Test func brokenSyntaxIsInvalid() {
        for tex in [#"\frac{a}{b"#, #"\foo{x}"#, #"\begin{nope} a \end{nope}"#,
                    #"{a"#, #"a}"#, #"\left( a"#] {
            #expect(!FormulaValidity.compute(tex).isValid, "\(tex)")
        }
    }

    @Test func emptyAndBlankAreInvalid() {
        for tex in ["", " ", "  \t "] {
            #expect(FormulaValidity.compute(tex) == .invalid(message: "Empty formula"))
        }
    }

    // MARK: Aliases

    @Test func aliasedCommandsBecomeValid() {
        let aliased = [
            #"\dfrac{a}{b}"#, #"\tfrac{a}{b}"#, #"a \implies b"#, #"a \impliedby b"#,
            #"\varnothing"#, #"\operatorname{lcm}(a,b)"#,
            #"\begin{align} a &= b \\ c &= d \end{align}"#,
            #"\begin{align*} a &= b \end{align*}"#,
            #"a \bmod n"#, #"a \equiv b \pmod{n}"#,
            #"\dfrac{\operatorname{sin} x}{2}"#,
        ]
        for tex in aliased {
            let answer = FormulaValidity.compute(tex)
            #expect(answer.isValid, "\(tex) should be rescued by an alias: \(answer)")
        }
    }

    @Test func aliasRewrites() {
        #expect(TeXAliases.resolve(#"\dfrac{a}{b}"#) == #"\frac{a}{b}"#)
        #expect(TeXAliases.resolve(#"\operatorname{lcm}(a,b)"#) == #"\mathrm{lcm}(a,b)"#)
        #expect(TeXAliases.resolve(#"\begin{align*}x\end{align*}"#)
                == #"\begin{aligned}x\end{aligned}"#)
    }

    @Test func aliasMatchesWholeCommandsOnly() {
        // `\dfracs` and `\\dfrac` (a line break, then text) are not `\dfrac`.
        #expect(TeXAliases.resolve(#"\dfracs"#) == #"\dfracs"#)
        #expect(TeXAliases.resolve(#"a \\dfrac"#) == #"a \\dfrac"#)
        #expect(TeXAliases.resolve(#"\impliesx"#) == #"\impliesx"#)
    }

    @Test func textWithoutBackslashesIsUntouched() {
        #expect(TeXAliases.resolve("x^2 + y_1") == "x^2 + y_1")
    }

    @Test func validAnswerCarriesTheResolvedTeX() {
        #expect(FormulaValidity.compute(#"\dfrac{1}{2}"#).tex == #"\frac{1}{2}"#)
        #expect(FormulaValidity.compute(#"\cancel{x}"#).tex == nil)
    }

    @Test func cacheAgreesWithCompute() {
        FormulaValidity.clearCache()
        for tex in supported + unsupported + ["", #"\dfrac{a}{b}"#] {
            #expect(FormulaValidity.check(tex) == FormulaValidity.compute(tex))
            #expect(FormulaValidity.check(tex) == FormulaValidity.compute(tex))
        }
    }
}
