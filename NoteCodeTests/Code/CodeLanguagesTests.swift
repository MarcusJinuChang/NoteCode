//
//  CodeLanguagesTests.swift
//  NoteCodeTests
//
//  v3 phase 4: C, JavaScript, Rust, Go and SQL join C++, Java and Python.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Code languages")
struct CodeLanguagesTests {

    // MARK: Tags and names

    @Test("Every tag people write lands on its language", arguments: [
        ("c", CodeLanguage.c),
        ("C", .c),
        ("js", .javascript), ("javascript", .javascript), ("node", .javascript), ("nodejs", .javascript), ("mjs", .javascript),
        ("rs", .rust), ("rust", .rust),
        ("go", .go), ("golang", .go),
        ("sql", .sql), ("sqlite", .sql), ("mysql", .sql), ("postgres", .sql), ("postgresql", .sql), ("pgsql", .sql),
        // And the three that were already there, so a typo in the table above
        // can't have moved one.
        ("c++", .cpp), ("cpp", .cpp), ("cc", .cpp), ("cxx", .cpp),
        ("java", .java), ("py", .python), ("python3", .python),
    ])
    func tags(tag: String, language: CodeLanguage) {
        #expect(CodeLanguage(tag: tag) == language)
    }

    @Test("Tags the app doesn't know stay unknown", arguments: ["ruby", "swift", "kotlin", "c#", "cs", "objc", "", "jav"])
    func unknownTags(tag: String) {
        #expect(CodeLanguage(tag: tag) == nil)
    }

    @Test("Each language has its own name, canonical name and highlight.js name")
    func names() {
        let all = CodeLanguage.allCases
        #expect(all.count == 8)
        #expect(Set(all.map(\.displayName)).count == all.count)
        #expect(Set(all.map(\.canonicalName)).count == all.count)
        #expect(Set(all.map(\.highlightName)).count == all.count)
        #expect(all.map(\.displayName) == ["C++", "Java", "Python", "C", "JavaScript", "Rust", "Go", "SQL"])
    }

    @Test("The raw value is a tag the language reads back as itself", arguments: CodeLanguage.allCases)
    func rawValueRoundTrips(language: CodeLanguage) {
        // `insertCodeBlock` writes the raw value after the fence.
        #expect(CodeLanguage(tag: language.rawValue) == language)
    }

    @Test("Only SQL is without a Run button")
    func canRun() {
        #expect(CodeLanguage.allCases.filter { !$0.canRun } == [.sql])
    }

    // MARK: highlight.js

    @Test("highlight.js colours each language by its own name", arguments: [
        (CodeLanguage.c, "#include <stdio.h>\nint main(void) { return 0; }"),
        (.javascript, "const add = (a, b) => a + 1;"),
        (.rust, "fn main() { let y: i32 = 1; }"),
        (.go, "func main() { var y int = 1 }"),
        (.sql, "SELECT name FROM users WHERE id = 1;"),
        (.cpp, "int x = 0;"),
        (.java, "class A { int x = 0; }"),
        (.python, "print(\"hi\")"),
    ])
    func highlights(language: CodeLanguage, code: String) async {
        #if canImport(UIKit)
        let runs = await HighlightSwiftHighlighter()
            .colorRuns(for: code, languageTag: language.highlightName, appearance: .light)
        #expect(!runs.isEmpty, "\(language.highlightName) gave no colours")
        #endif
    }

    // MARK: Running

    private static let sample = "int main() { return 0; }"

    /// The Compiler Explorer session a link carries, decoded.
    private struct Session {
        var language: String
        var compiler: String
        var options: String
        var source: String
    }

    private static func session(in url: URL) throws -> Session {
        let prefix = "https://godbolt.org/clientstate/"
        let absolute = url.absoluteString
        try #require(absolute.hasPrefix(prefix))
        let encoded = String(absolute.dropFirst(prefix.count)).removingPercentEncoding ?? ""
        let data = try #require(Data(base64Encoded: encoded))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try #require((json["sessions"] as? [[String: Any]])?.first)
        let executor = try #require((session["executors"] as? [[String: Any]])?.first)
        let compiler = try #require(executor["compiler"] as? [String: Any])
        return Session(
            language: session["language"] as? String ?? "",
            compiler: compiler["id"] as? String ?? "",
            options: compiler["options"] as? String ?? "",
            source: session["source"] as? String ?? ""
        )
    }

    @Test("Compiler Explorer takes C, C++, Python, Rust and Go in the link, with the pinned compilers", arguments: [
        (CodeLanguage.cpp, "c++", "g162"),
        (.python, "python", "python314"),
        (.c, "c", "cg162"),
        (.rust, "rust", "r1990"),
        (.go, "go", "gl1260"),
    ])
    func compilerExplorer(language: CodeLanguage, site: String, compiler: String) throws {
        let request = CodeDestination.request(for: Self.sample, language: language)
        #expect(request.destination == .compilerExplorer)
        #expect(request.delivery == .inURL)
        #expect(request.pasteboardCode == nil)
        let session = try Self.session(in: request.url)
        #expect(session.language == site)
        #expect(session.compiler == compiler)
        #expect(session.source == Self.sample)
    }

    @Test("Java and JavaScript can't run on Compiler Explorer, so they go where they can", arguments: [CodeLanguage.java, .javascript])
    func compilerExplorerFallsBack(language: CodeLanguage) {
        // Java: a fixed file name. JavaScript: its only compilers are V8
        // builds that show bytecode and can't execute.
        #expect(!CodeDestination.compilerExplorer.supports(language))
        let request = CodeDestination.request(for: Self.sample, language: language)
        #expect(request.destination == .programiz)
        #expect(request.delivery == .pasteboard)
        #expect(request.pasteboardCode == Self.sample)
    }

    /// A block too long for a Compiler Explorer link reaches these.
    @Test("Every language but SQL has a page on Programiz", arguments: [
        (CodeLanguage.cpp, "https://www.programiz.com/cpp-programming/online-compiler/"),
        (.python, "https://www.programiz.com/python-programming/online-compiler/"),
        (.c, "https://www.programiz.com/c-programming/online-compiler/"),
        (.rust, "https://www.programiz.com/rust/online-compiler/"),
        (.go, "https://www.programiz.com/golang/online-compiler/"),
        (.java, "https://www.programiz.com/java-programming/online-compiler/"),
        (.javascript, "https://www.programiz.com/javascript/online-compiler/"),
    ])
    func programiz(language: CodeLanguage, expected: String) {
        #expect(CodeDestination.programiz.supports(language))
        let long = String(repeating: "x = 1 # a line long enough to fill a link\n", count: 300)
        let code = CodeDestination.compilerExplorer.supports(language) ? long : Self.sample
        let request = CodeDestination.request(for: code, language: language)
        #expect(request.destination == .programiz)
        #expect(request.delivery == .pasteboard)
        #expect(request.url.absoluteString == expected)
    }

    @Test("SQL is in no destination's list")
    func sqlIsCopyOnly() {
        #expect(!CodeDestination.programiz.supports(.sql))
        #expect(!CodeDestination.compilerExplorer.supports(.sql))
    }

    // MARK: The menu

    @Test("The menu lists the languages, then Output, then Code")
    func menu() {
        #expect(CodeBlockKind.menu.map(\.displayName) ==
            ["C++", "Java", "Python", "C", "JavaScript", "Rust", "Go", "SQL", "Output", "Code"])
    }

    @Test("Only SQL carries a subtitle, and the two groups are the menu")
    func subtitles() {
        #expect(CodeBlockKind.menu.compactMap(\.subtitle) == ["Copy only"])
        #expect(CodeBlockKind.language(.sql).subtitle == "Copy only")
        #expect(CodeBlockKind.languages + CodeBlockKind.others == CodeBlockKind.menu)
    }

    @Test("A new block's tag", arguments: [
        (CodeBlockKind.language(.rust), "rust"), (.language(.cpp), "cpp"), (.output, "output"),
    ])
    func insertedTag(kind: CodeBlockKind, tag: String) {
        let edit = MarkdownFormatting.insertCodeBlock(kind: kind, in: "", selection: NSRange(location: 0, length: 0))
        #expect(edit.replacement == "```\(tag)\n\n```")
        #expect(MarkdownFormatting.insertCodeBlock(kind: .plain, in: "", selection: NSRange(location: 0, length: 0)).replacement == "```\n\n```")
    }
}
