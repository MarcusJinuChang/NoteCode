//
//  CodeIndentTests.swift
//  NoteCodeTests
//
//  v3 phase 4: what Return, Tab and ⇧Tab do in code. Tables of text in and
//  text out, with ‸ for the caret and ⟦ ⟧ around a selection.
//

#if canImport(UIKit)

import Foundation
import Testing
@testable import NoteCode

@Suite("Indentation in code")
struct CodeIndentTests {

    // MARK: Helpers

    /// A note holding `body` in a fenced block of `tag`, with the caret
    /// marked in the body. The note, and the selection in it.
    private static func note(_ body: String, tag: String = "cpp", closed: Bool = true) -> (text: String, selection: NSRange) {
        var text = "Prose.\n```\(tag)\n" + body + (closed ? "\n```\nAfter.\n" : "")
        var location = 0
        if let caret = text.range(of: "‸") {
            location = (text[..<caret.lowerBound] as Substring).utf16.count
            text.removeSubrange(caret)
        }
        return (text, NSRange(location: location, length: 0))
    }

    private static func ranges(_ text: String) -> [CodeRange] {
        DocumentCache().codeRanges(for: text)
    }

    /// Applies an edit and marks where the caret is, for comparing.
    private static func shown(_ edit: TextEdit, to text: String) -> String {
        var result = edit.applied(to: text) as NSString
        result = result.replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "‸") as NSString
        return result as String
    }

    /// Return at the caret in `body`. The body afterwards, caret marked, or
    /// `nil` for a plain newline.
    private static func pressReturn(_ body: String, tag: String = "cpp", width: Int = 4, closed: Bool = true) -> String? {
        let (text, selection) = note(body, tag: tag, closed: closed)
        guard let edit = CodeIndent.returnEdit(
            in: text as NSString, selection: selection, codeRanges: ranges(text), width: width
        ) else { return nil }
        let result = shown(edit, to: text)
        // Only the body, as the tests write it.
        return String(result.dropFirst("Prose.\n```\(tag)\n".count)).components(separatedBy: closed ? "\n```\nAfter.\n" : "\u{0}")[0]
    }

    // MARK: Return, C++ and Java

    @Test("Return keeps the line's indent", arguments: [
        ("int x = 1;‸", nil as String?),
        ("    int x = 1;‸", "    int x = 1;\n    ‸"),
        ("        return x;‸", "        return x;\n        ‸"),
        ("\tint x = 1;‸", "\tint x = 1;\n\t‸"),
        ("‸int x;", nil),
    ])
    func keepsIndent(body: String, expected: String?) {
        #expect(Self.pressReturn(body) == expected)
    }

    @Test("After { ( or [ it goes one level deeper", arguments: [
        ("int main() {‸", "int main() {\n    ‸"),
        ("    if (x) {‸", "    if (x) {\n        ‸"),
        ("    foo(‸", "    foo(\n        ‸"),
        ("    int a[] = {‸", "    int a[] = {\n        ‸"),
        ("    int a[‸", "    int a[\n        ‸"),
        ("\tfoo() {‸", "\tfoo() {\n\t\t‸"),
        ("    } else {‸", "    } else {\n        ‸"),
        ("    if (x) {   ‸", "    if (x) {   \n        ‸"),
    ])
    func deeper(body: String, expected: String) {
        #expect(Self.pressReturn(body) == expected)
    }

    @Test("Two spaces when the setting says two")
    func width2() {
        #expect(Self.pressReturn("if (x) {‸", width: 2) == "if (x) {\n  ‸")
        #expect(Self.pressReturn("  if (x) {‸", width: 2) == "  if (x) {\n    ‸")
    }

    @Test("Between a bracket and its closer, the closer goes to its own line", arguments: [
        ("for (i = 0; i < n; i++) {‸}", "for (i = 0; i < n; i++) {\n    ‸\n}"),
        ("    if (x) {‸}", "    if (x) {\n        ‸\n    }"),
        ("    foo(‸)", "    foo(\n        ‸\n    )"),
        ("    int a[] = {‸};", "    int a[] = {\n        ‸\n    };"),
        ("    int a[‸]", "    int a[\n        ‸\n    ]"),
        ("    if (x) {  ‸  }", "    if (x) {  \n        ‸\n    }"),
        ("\tfoo() {‸}", "\tfoo() {\n\t\t‸\n\t}"),
    ])
    func splitsBraces(body: String, expected: String) {
        #expect(Self.pressReturn(body) == expected)
    }

    @Test("A bracket and the wrong closer aren't a pair")
    func mismatched() {
        #expect(Self.pressReturn("    foo(‸}") == "    foo(\n        ‸}")
        #expect(Self.pressReturn("    if (x) {‸)") == "    if (x) {\n        ‸)")
    }

    @Test("What follows the caret moves down with it")
    func textAfter() {
        #expect(Self.pressReturn("    int x = 1;‸ // note") == "    int x = 1;\n    ‸ // note")
        #expect(Self.pressReturn("    int x = ‸1;") == "    int x = \n    ‸1;")
        // After a comma it is the same level: only an opener deepens it.
        #expect(Self.pressReturn("    foo(a, ‸b);") == "    foo(a, \n    ‸b);")
    }

    @Test("A blank line stays blank: the indent moves down, not copied")
    func blankStaysBlank() {
        #expect(Self.pressReturn("    ‸") == "\n    ‸")
        #expect(Self.pressReturn("int x;\n    ‸\nint y;") == "int x;\n\n    ‸\nint y;")
        // With the caret in the indent, the rest of the indent goes with the text.
        #expect(Self.pressReturn("  ‸  foo();") == "\n  ‸  foo();")
    }

    @Test("No deeper after a colon outside Python", arguments: ["cpp", "java", "c", "javascript", "rust", "go", "sql", ""])
    func colonOnlyInPython(tag: String) {
        #expect(Self.pressReturn("    case 1:‸", tag: tag) == "    case 1:\n    ‸")
        #expect(Self.pressReturn("public:‸", tag: tag) == nil)
    }

    @Test("Java")
    func java() {
        #expect(Self.pressReturn("public class Main {‸", tag: "java") == "public class Main {\n    ‸")
        #expect(Self.pressReturn("    public static void main(String[] args) {‸}", tag: "java")
            == "    public static void main(String[] args) {\n        ‸\n    }")
        #expect(Self.pressReturn("        System.out.println(x);‸", tag: "java") == "        System.out.println(x);\n        ‸")
        #expect(Self.pressReturn("    }‸", tag: "java") == "    }\n    ‸")
    }

    // MARK: Return, Python

    @Test("Python: a colon goes one level deeper", arguments: [
        ("def push(self, x):‸", "def push(self, x):\n    ‸"),
        ("    def push(self, x):‸", "    def push(self, x):\n        ‸"),
        ("class Stack:‸", "class Stack:\n    ‸"),
        ("    else:‸", "    else:\n        ‸"),
        ("    if x:   ‸", "    if x:   \n        ‸"),
        ("    return x‸", "    return x\n    ‸"),
        ("items = {‸", "items = {\n    ‸"),
        ("print(‸)", "print(\n    ‸\n)"),
    ])
    func python(body: String, expected: String) {
        #expect(Self.pressReturn(body, tag: "python") == expected)
    }

    @Test("Python: a comment ending in a colon isn't a block")
    func pythonComment() {
        #expect(Self.pressReturn("    # note:‸", tag: "python") == "    # note:\n    ‸")
    }

    @Test("Python with a two-space indent", arguments: ["py", "python3"])
    func python2(tag: String) {
        #expect(Self.pressReturn("def f():‸", tag: tag, width: 2) == "def f():\n  ‸")
    }

    // MARK: Where Return is plain

    @Test("Return on a fence line, in prose, or in output is a plain newline")
    func plainElsewhere() {
        let text = "Prose {\n```cpp\nint x {\n```\nAfter {\n```output\n    {\n```\n"
        let blocks = Self.ranges(text)
        func press(at marker: String, offset: Int = 0) -> TextEdit? {
            let location = (text as NSString).range(of: marker).location + offset
            return CodeIndent.returnEdit(in: text as NSString, selection: NSRange(location: location, length: 0), codeRanges: blocks, width: 4)
        }
        #expect(press(at: "Prose {", offset: 7) == nil, "prose")
        #expect(press(at: "```cpp", offset: 6) == nil, "the opening fence")
        #expect(press(at: "```\nAfter") == nil, "the closing fence, at its start")
        #expect(press(at: "```\nAfter", offset: 3) == nil, "the closing fence, at its end")
        #expect(press(at: "After {", offset: 7) == nil, "prose after a block")
        #expect(press(at: "    {", offset: 5) == nil, "an output block")
        #expect(press(at: "int x {", offset: 7) != nil, "and code is code")
    }

    @Test("An unclosed block is code to the end of the note")
    func unclosed() {
        #expect(Self.pressReturn("int main() {‸", closed: false) == "int main() {\n    ‸")
        #expect(Self.pressReturn("    int x;‸", closed: false) == "    int x;\n    ‸")
    }

    @Test("A selection is replaced by the new line")
    func selection() {
        let text = "```cpp\n    foo(abc);\n```"
        let start = (text as NSString).range(of: "abc").location
        let edit = CodeIndent.returnEdit(
            in: text as NSString, selection: NSRange(location: start, length: 3), codeRanges: Self.ranges(text), width: 4
        )
        #expect(edit.map { Self.shown($0, to: text) } == "```cpp\n    foo(\n        ‸\n    );\n```")
    }

    @Test("A selection reaching out of the block is left alone")
    func selectionOutOfBlock() {
        let text = "```cpp\nint x;\n```\nAfter\n"
        let selection = NSRange(location: 8, length: 14)
        #expect(CodeIndent.returnEdit(in: text as NSString, selection: selection, codeRanges: Self.ranges(text), width: 4) == nil)
    }

    // MARK: Content

    @Test("The code lines of a block are between its fences")
    func content() {
        for (text, expected) in [
            ("```cpp\nab\ncd\n```\nx", "ab\ncd\n"),
            ("```cpp\n```\n", ""),
            ("```cpp\n\n```", "\n"),
            ("```cpp\nab\ncd", "ab\ncd"),
            ("```cpp\nab\ncd\n", "ab\ncd\n"),
            ("```cpp", ""),
        ] {
            let block = Self.ranges(text)[0]
            let range = CodeIndent.contentRange(of: block, in: text as NSString)
            #expect(range.map { (text as NSString).substring(with: $0) } == expected, "\(text.debugDescription)")
        }
    }

    // MARK: Tab and ⇧Tab

    /// ⇥ or ⇧⇥ on the body, with the selection marked ⟦ ⟧ or the caret ‸.
    private static func tab(_ body: String, outdent: Bool = false, width: Int = 4, tag: String = "cpp") -> String? {
        var body = body
        var selection = NSRange(location: 0, length: 0)
        let prefix = "Prose.\n```\(tag)\n"
        if let open = body.range(of: "⟦"), let close = body.range(of: "⟧") {
            let start = body[..<open.lowerBound].utf16.count
            let inside = body[open.upperBound..<close.lowerBound].utf16.count
            body = body.replacingOccurrences(of: "⟦", with: "").replacingOccurrences(of: "⟧", with: "")
            selection = NSRange(location: prefix.utf16.count + start, length: inside)
        } else if let caret = body.range(of: "‸") {
            selection = NSRange(location: prefix.utf16.count + body[..<caret.lowerBound].utf16.count, length: 0)
            body = body.replacingOccurrences(of: "‸", with: "")
        }
        let text = prefix + body + "\n```\nAfter.\n"
        guard let edit = CodeIndent.indentEdit(
            in: text as NSString, selection: selection, outdent: outdent, codeRanges: ranges(text), width: width
        ) else { return nil }
        let result = (edit.applied(to: text) as NSString)
        let marks = edit.selection.length == 0
            ? result.replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "‸")
            : (result.replacingCharacters(in: NSRange(location: NSMaxRange(edit.selection), length: 0), with: "⟧") as NSString)
                .replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "⟦")
        return String((marks as String).dropFirst(prefix.count)).components(separatedBy: "\n```\nAfter.\n")[0]
    }

    @Test("⇥ indents the line the caret is on, one level", arguments: [
        ("int x;‸", "    int x;‸"),
        ("in‸t x;", "    in‸t x;"),
        ("‸int x;", "    ‸int x;"),
        ("    int x;‸", "        int x;‸"),
        ("‸", "    ‸"),
        ("\tint x;‸", "\t\tint x;‸"),
    ])
    func indentCaret(body: String, expected: String) {
        #expect(Self.tab(body) == expected)
    }

    @Test("⇥ with a two-space indent")
    func indent2() {
        #expect(Self.tab("int x;‸", width: 2) == "  int x;‸")
    }

    @Test("⇧⇥ takes a level off, or what there is of one", arguments: [
        ("        int x;‸", "    int x;‸"),
        ("    int x;‸", "int x;‸"),
        ("  int x;‸", "int x;‸"),
        (" int x;‸", "int x;‸"),
        ("\tint x;‸", "int x;‸"),
        ("\t\tint x;‸", "\tint x;‸"),
        ("    ‸int x;", "‸int x;"),
        ("  ‸int x;", "‸int x;"),
    ])
    func outdentCaret(body: String, expected: String) {
        #expect(Self.tab(body, outdent: true) == expected)
    }

    @Test("⇧⇥ with nothing to take off gives the key back")
    func outdentNothing() {
        #expect(Self.tab("int x;‸", outdent: true) == nil)
        #expect(Self.tab("‸", outdent: true) == nil)
    }

    @Test("A selection indents every line it touches, blank lines excepted")
    func indentSelection() {
        #expect(Self.tab("⟦a;\n\nb;⟧") == "⟦    a;\n\n    b;⟧")
        #expect(Self.tab("a;\n⟦b;\nc;⟧\nd;") == "a;\n⟦    b;\n    c;⟧\nd;")
        // Starting mid-line takes in the whole line, and the selection moves
        // with the text.
        #expect(Self.tab("a;\nb⟦b;\nc⟧c;") == "a;\n    b⟦b;\n    c⟧c;")
    }

    @Test("A selection outdents every line it touches")
    func outdentSelection() {
        #expect(Self.tab("⟦    a;\n        b;\n  c;⟧", outdent: true) == "⟦a;\n    b;\nc;⟧")
    }

    @Test("Tab keeps the indent unit of the line it works on")
    func mixedUnits() {
        #expect(Self.tab("⟦\ta;\n    b;⟧") == "⟦\t\ta;\n        b;⟧")
    }

    @Test("A caret or selection outside the code lines isn't Tab's")
    func tabElsewhere() {
        let text = "Prose.\n```cpp\nint x;\n```\nAfter.\n"
        let blocks = Self.ranges(text)
        func edit(_ marker: String, offset: Int = 0, length: Int = 0, outdent: Bool = false) -> TextEdit? {
            let location = (text as NSString).range(of: marker).location + offset
            return CodeIndent.indentEdit(
                in: text as NSString, selection: NSRange(location: location, length: length),
                outdent: outdent, codeRanges: blocks, width: 4
            )
        }
        #expect(edit("Prose.") == nil)
        #expect(edit("```cpp") == nil, "the opening fence")
        #expect(edit("```\nAfter") == nil, "the closing fence")
        #expect(edit("After.") == nil)
        #expect(edit("int x;", length: 20) == nil, "a selection running out of the block")
        #expect(edit("Prose.", length: 12) == nil, "a selection running into it")
        #expect(edit("int x;") != nil)
    }

    @Test("Output isn't indented")
    func outputBlock() {
        let text = "```output\nok\n```\n"
        #expect(CodeIndent.indentEdit(in: text as NSString, selection: NSRange(location: 11, length: 0), outdent: false, codeRanges: Self.ranges(text), width: 4) == nil)
        #expect(CodeIndent.returnEdit(in: text as NSString, selection: NSRange(location: 12, length: 0), codeRanges: Self.ranges(text), width: 4) == nil)
    }

    // MARK: The setting

    @Test("The width is 2 or 4, and 4 for anything else")
    func widthSetting() {
        #expect(CodeIndent.widths == [2, 4])
        #expect(CodeIndent.validWidth(2) == 2)
        #expect(CodeIndent.validWidth(4) == 4)
        #expect(CodeIndent.validWidth(3) == 4)
        #expect(CodeIndent.validWidth(0) == 4)
        #expect(CodeIndent.validWidth(nil) == 4)
        #expect(CodeIndent.widthKey == "indentWidth")

        let defaults = UserDefaults(suiteName: "CodeIndentTests.\(UUID().uuidString)")!
        #expect(CodeIndent.width(from: defaults) == 4)
        defaults.set(2, forKey: CodeIndent.widthKey)
        #expect(CodeIndent.width(from: defaults) == 2)
        defaults.set(8, forKey: CodeIndent.widthKey)
        #expect(CodeIndent.width(from: defaults) == 4)
    }
}

#endif
