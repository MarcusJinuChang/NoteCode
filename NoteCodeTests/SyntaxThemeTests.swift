//
//  SyntaxThemeTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Syntax theme")
struct SyntaxThemeTests {

    // MARK: Helpers

    private static func hex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())
        )
    }

    /// WCAG relative luminance of an sRGB hex colour.
    private static func luminance(_ hex: String) -> Double {
        let value = UInt32(hex, radix: 16) ?? 0
        let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { byte -> Double in
            let c = Double(byte) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private static func contrast(_ a: String, _ b: String) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// The text a colour was given to, for each run.
    private static func tokens(_ tag: String, _ code: String, _ appearance: HighlightAppearance) async -> [String: String] {
        let runs = await HighlightSwiftHighlighter().colorRuns(for: code, languageTag: tag, appearance: appearance)
        let source = code as NSString
        var found: [String: String] = [:]
        for run in runs { found[source.substring(with: run.range)] = hex(run.color) }
        return found
    }

    // MARK: Contrast

    /// `secondarySystemBackground`, the code panel, as the design lists it.
    private static let panel: [HighlightAppearance: String] = [.light: "F2F2F7", .dark: "1C1C1E"]

    @Test("Every role is 4.5:1 or better on its panel", arguments: [HighlightAppearance.light, .dark])
    func contrastOnPanel(appearance: HighlightAppearance) {
        let theme = SyntaxTheme.theme(for: appearance)
        let roles = [theme.keyword, theme.type, theme.function, theme.string, theme.number, theme.comment]
        for role in roles {
            let ratio = Self.contrast(role.hex, Self.panel[appearance]!)
            #expect(ratio >= 4.5, "\(role.hex) on \(appearance) is \(ratio):1")
        }
    }

    // MARK: Mapping, through the real highlighter

    @Test("C++ tokens take the design's colours", arguments: [HighlightAppearance.light, .dark])
    func cpp(appearance: HighlightAppearance) async {
        let t = SyntaxTheme.theme(for: appearance)
        let found = await Self.tokens(
            "cpp",
            "class Foo { // note\n  int add(int a) { return a + 42; }\n};\nstd::string s = \"hi\"; bool ok = true;",
            appearance
        )
        #expect(found["class"] == t.keyword.hex)
        #expect(found["return"] == t.keyword.hex)
        #expect(found["true"] == t.keyword.hex)
        #expect(found["Foo"] == t.type.hex)
        #expect(found["int"] == t.type.hex)
        #expect(found["bool"] == t.type.hex)
        #expect(found["add"] == t.function.hex)
        #expect(found["42"] == t.number.hex)
        #expect(found["\"hi\""] == t.string.hex)
        #expect(found["// note"] == t.comment.hex)
    }

    @Test("Java tokens take the design's colours", arguments: [HighlightAppearance.light, .dark])
    func java(appearance: HighlightAppearance) async {
        let t = SyntaxTheme.theme(for: appearance)
        let found = await Self.tokens(
            "java",
            "public class Main {\n  static int add(int a) { return a + 42; }\n  String s = \"hi\"; // note\n}",
            appearance
        )
        #expect(found["public"] == t.keyword.hex)
        #expect(found["Main"] == t.type.hex)
        #expect(found["String"] == t.type.hex)
        #expect(found["add"] == t.function.hex)
        #expect(found["42"] == t.number.hex)
        #expect(found["\"hi\""] == t.string.hex)
        #expect(found["// note"] == t.comment.hex)
    }

    @Test("Python tokens take the design's colours", arguments: [HighlightAppearance.light, .dark])
    func python(appearance: HighlightAppearance) async {
        let t = SyntaxTheme.theme(for: appearance)
        let found = await Self.tokens(
            "python",
            "def greet(name):\n    # note\n    return f\"Hello, {name}!\" + str(3)\n\nclass A(B): pass",
            appearance
        )
        #expect(found["def"] == t.keyword.hex)
        #expect(found["greet"] == t.function.hex)
        #expect(found["str"] == t.type.hex)
        #expect(found["A"] == t.type.hex)
        #expect(found["3"] == t.number.hex)
        #expect(found["# note"] == t.comment.hex)
        #expect(found["f\"Hello, {name}!\""] == t.string.hex)
    }

    // MARK: The languages added in v3

    @Test("C tokens take the design's colours", arguments: [HighlightAppearance.light, .dark])
    func c(appearance: HighlightAppearance) async {
        let t = SyntaxTheme.theme(for: appearance)
        let found = await Self.tokens(
            "c",
            "#include <stdio.h>\nint main(void) {\n  // note\n  char *s = \"hi\"; return 42;\n}",
            appearance
        )
        #expect(found["return"] == t.keyword.hex)
        #expect(found["int"] == t.type.hex)
        #expect(found["char"] == t.type.hex)
        #expect(found["void"] == t.type.hex)
        #expect(found["main"] == t.function.hex)
        #expect(found["42"] == t.number.hex)
        #expect(found["\"hi\""] == t.string.hex)
        #expect(found["// note"] == t.comment.hex)
    }

    @Test("JavaScript tokens take the design's colours", arguments: [HighlightAppearance.light, .dark])
    func javascript(appearance: HighlightAppearance) async {
        let t = SyntaxTheme.theme(for: appearance)
        let found = await Self.tokens(
            "javascript",
            "const add = (a, b) => a + 42; // note\nclass Foo {}\nfunction go() { return \"hi\"; }\nlet n = null;",
            appearance
        )
        #expect(found["const"] == t.keyword.hex)
        #expect(found["class"] == t.keyword.hex)
        #expect(found["function"] == t.keyword.hex)
        #expect(found["null"] == t.keyword.hex)
        #expect(found["Foo"] == t.type.hex)
        #expect(found["go"] == t.function.hex)
        #expect(found["42"] == t.number.hex)
        #expect(found["\"hi\""] == t.string.hex)
        #expect(found["// note"] == t.comment.hex)
    }

    @Test("Rust tokens take the design's colours", arguments: [HighlightAppearance.light, .dark])
    func rust(appearance: HighlightAppearance) async {
        let t = SyntaxTheme.theme(for: appearance)
        let found = await Self.tokens(
            "rust",
            "fn add(a: i32) -> i32 { let s = \"hi\"; a + 42 } // note\nstruct P;\nimpl P { fn new() -> P { P } }",
            appearance
        )
        #expect(found["fn"] == t.keyword.hex)
        #expect(found["let"] == t.keyword.hex)
        #expect(found["struct"] == t.keyword.hex)
        #expect(found["i32"] == t.type.hex)
        #expect(found["P"] == t.type.hex)
        #expect(found["add"] == t.function.hex)
        #expect(found["42"] == t.number.hex)
        #expect(found["\"hi\""] == t.string.hex)
        #expect(found["// note"] == t.comment.hex)
    }

    @Test("Go tokens take the design's colours", arguments: [HighlightAppearance.light, .dark])
    func go(appearance: HighlightAppearance) async {
        let t = SyntaxTheme.theme(for: appearance)
        let found = await Self.tokens(
            "go",
            "package main\nfunc add(a int) int { s := \"hi\"; return a + 42 } // note\ntype P struct{}",
            appearance
        )
        #expect(found["package"] == t.keyword.hex)
        #expect(found["func"] == t.keyword.hex)
        #expect(found["return"] == t.keyword.hex)
        #expect(found["int"] == t.type.hex)
        #expect(found["add"] == t.function.hex)
        #expect(found["42"] == t.number.hex)
        #expect(found["\"hi\""] == t.string.hex)
        #expect(found["// note"] == t.comment.hex)
    }

    @Test("SQL tokens take the design's colours", arguments: [HighlightAppearance.light, .dark])
    func sql(appearance: HighlightAppearance) async {
        let t = SyntaxTheme.theme(for: appearance)
        let found = await Self.tokens(
            "sql",
            "SELECT name FROM users WHERE id = 42; -- note\nINSERT INTO t VALUES ('hi');\nCREATE TABLE t (id INT);",
            appearance
        )
        #expect(found["SELECT"] == t.keyword.hex)
        #expect(found["FROM"] == t.keyword.hex)
        #expect(found["WHERE"] == t.keyword.hex)
        #expect(found["INT"] == t.type.hex)
        #expect(found["42"] == t.number.hex)
        #expect(found["'hi'"] == t.string.hex)
        #expect(found["-- note"] == t.comment.hex)
    }

    @Test("Every colour a new language produces is one of the theme's six, all 4.5:1 on the panel",
          arguments: [HighlightAppearance.light, .dark])
    func onlyThemeColours(appearance: HighlightAppearance) async {
        let theme = SyntaxTheme.theme(for: appearance)
        let allowed = Set([theme.keyword, theme.type, theme.function, theme.string, theme.number, theme.comment].map(\.hex))
        let samples: [CodeLanguage: String] = [
            .c: "#include <stdio.h>\nstatic const int n = 3; /* x */ int main(void) { return n; }",
            .javascript: "export default async function f(x) { for (const i of x) await i?.y ?? `t${i}`; }",
            .rust: "#[derive(Debug)] pub struct S<'a> { r: &'a str } impl S<'_> { pub fn f(&self) -> Option<u8> { None } }",
            .go: "package main\nimport \"fmt\"\nfunc main() { ch := make(chan int); go func() { ch <- 1 }(); fmt.Println(<-ch) }",
            .sql: "WITH t AS (SELECT a, COUNT(*) FROM b GROUP BY a) SELECT * FROM t LEFT JOIN u ON t.a = u.a ORDER BY 1;",
        ]
        for (language, code) in samples {
            let runs = await HighlightSwiftHighlighter()
                .colorRuns(for: code, languageTag: language.highlightName, appearance: appearance)
            #expect(!runs.isEmpty, "\(language)")
            for run in runs {
                let hex = Self.hex(run.color)
                #expect(allowed.contains(hex), "\(language): \((code as NSString).substring(with: run.range)) is \(hex)")
                #expect(Self.contrast(hex, Self.panel[appearance]!) >= 4.5)
            }
        }
    }

    // MARK: Plain text

    @Test("Plain code gets no colour run, so it keeps the editor's label colour",
          arguments: [HighlightAppearance.light, .dark])
    func plainIsLeftAlone(appearance: HighlightAppearance) async {
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: "int x = (y + z);", languageTag: "cpp", appearance: appearance)

        // Without the sentinel the importer paints these black, which is
        // unreadable on the dark panel.
        for run in runs {
            #expect(!SyntaxTheme.isPlain(run.color))
            #expect(Self.hex(run.color) != "000000")
        }
        #expect(!runs.isEmpty)
    }
}

#endif
