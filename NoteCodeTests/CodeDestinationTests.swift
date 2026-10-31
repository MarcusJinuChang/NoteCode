//
//  CodeDestinationTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Handing a code block to an online compiler")
struct CodeDestinationTests {

    // MARK: Which site gets it

    @Test("Compiler Explorer gets what it can run; Java and JavaScript go to Programiz")
    func siteByLanguage() {
        for language in CodeLanguage.allCases where language.canRun {
            let expected: CodeDestination = [.java, .javascript].contains(language) ? .programiz : .compilerExplorer
            #expect(CodeDestination.request(for: "x", language: language).destination == expected, "\(language)")
        }
    }

    @Test("Compiler Explorer is the one that can't take Java, or JavaScript")
    func compilerExplorerLanguages() {
        #expect(CodeDestination.compilerExplorer.supports(.cpp))
        #expect(CodeDestination.compilerExplorer.supports(.python))
        #expect(CodeDestination.compilerExplorer.supports(.c))
        #expect(CodeDestination.compilerExplorer.supports(.rust))
        #expect(CodeDestination.compilerExplorer.supports(.go))
        #expect(!CodeDestination.compilerExplorer.supports(.java))
        #expect(!CodeDestination.compilerExplorer.supports(.javascript))
    }

    @Test("Programiz takes every language that runs")
    func programizTakesEverything() {
        for language in CodeLanguage.allCases where language.canRun {
            #expect(CodeDestination.programiz.supports(language), "\(language)")
        }
    }

    // MARK: Delivery

    @Test("Programiz cannot be prefilled, so the code rides the pasteboard")
    func programizUsesPasteboard() {
        let request = CodeDestination.request(for: "class A {}", language: .java)

        #expect(request.destination == .programiz)
        #expect(request.delivery == .pasteboard)
        #expect(request.pasteboardCode == "class A {}")
    }

    @Test("Compiler Explorer carries the code, so nothing is copied")
    func compilerExplorerUsesTheLink() {
        let request = CodeDestination.request(for: "int main() {}", language: .cpp)

        #expect(request.delivery == .inURL)
        #expect(request.pasteboardCode == nil)
    }

    /// Exact addresses on purpose. The failure this guards against is a
    /// student landing on a compiler for another language, and only the whole
    /// path distinguishes those — "contains the language" passes for both.
    @Test("Java and JavaScript land on their own Programiz pages")
    func languageSpecificLandingPages() {
        #expect(CodeDestination.request(for: "x", language: .java).url.absoluteString
            == "https://www.programiz.com/java-programming/online-compiler/")
        #expect(CodeDestination.request(for: "x", language: .javascript).url.absoluteString
            == "https://www.programiz.com/javascript/online-compiler/")
    }

    // MARK: The Compiler Explorer link

    /// The shape verified against the live site on 11 September 2026: the
    /// session decodes back out of the path, and asking for an executor is what
    /// makes the student land on program output rather than assembly.
    @Test("The link decodes back to the block that was sent")
    func linkRoundTrips() throws {
        let code = "#include <iostream>\nint main() { std::cout << \"hi\"; }\n"
        let url = try #require(CodeDestination.compilerExplorerURL(code: code, language: .cpp))

        let state = try decodeClientState(from: url)
        let session = try #require((state["sessions"] as? [[String: Any]])?.first)

        #expect(session["source"] as? String == code)
        #expect(session["language"] as? String == "c++")
        #expect((session["executors"] as? [[String: Any]])?.count == 1)
    }

    @Test("Java produces no link at all, which is what makes it fall back")
    func javaHasNoLink() {
        #expect(CodeDestination.compilerExplorerURL(code: "class A {}", language: .java) == nil)
    }

    @Test("The same block always produces the same link")
    func linkIsStable() {
        let first = CodeDestination.compilerExplorerURL(code: "print(1)", language: .python)
        let second = CodeDestination.compilerExplorerURL(code: "print(1)", language: .python)

        #expect(first == second)
    }

    /// Base64 uses `+`, `/` and `=`, and the payload sits in the path, where all
    /// three mean something else.
    @Test("Nothing in the link needs escaping once it is built")
    func linkIsPathSafe() throws {
        // `~` and `?` encode to base64 runs that reliably contain `+` and `/`.
        let code = "a = b ?? c\nd = ~e\nprint('<>&')\n"
        let url = try #require(CodeDestination.compilerExplorerURL(code: code, language: .python))

        let payload = url.absoluteString.replacingOccurrences(
            of: "https://godbolt.org/clientstate/", with: ""
        )
        #expect(!payload.contains("+"))
        #expect(!payload.contains("/"))
        #expect(!payload.contains("="))
        #expect(try decodeClientState(from: url)["sessions"] != nil)
    }

    @Test("Slashes are not escaped, so comment-heavy code stays short")
    func slashesSurviveUnescaped() throws {
        let url = try #require(
            CodeDestination.compilerExplorerURL(code: "// note\nint x;", language: .cpp)
        )
        let json = try #require(decodedJSONString(from: url))

        #expect(json.contains("// note"))
        #expect(!json.contains("\\/\\/"))
    }

    /// The program travels in the request path, so it meets everything between
    /// the device and their server that has an opinion about how long one is.
    @Test("A block too long for a link goes to Programiz's page for its language, on the pasteboard")
    func oversizedCodeFallsBack() {
        let huge = String(repeating: "int aVeryLongVariableName = 0;\n", count: 500)

        #expect(CodeDestination.compilerExplorerURL(code: huge, language: .cpp) == nil)

        let request = CodeDestination.request(for: huge, language: .cpp)
        #expect(request.delivery == .pasteboard)
        #expect(request.pasteboardCode == huge)
        #expect(request.destination == .programiz)
        #expect(request.url.absoluteString == "https://www.programiz.com/cpp-programming/online-compiler/")
    }

    @Test("A block that just fits still travels in the link")
    func sizedCodeStillLinks() {
        let sized = String(repeating: "x = 1\n", count: 200)
        let url = CodeDestination.compilerExplorerURL(code: sized, language: .python)

        #expect(url != nil)
        #expect((url?.absoluteString.count ?? .max) <= CodeDestination.maximumLinkedCodeLength)
    }

    // MARK: Helpers

    private func decodedJSONString(from url: URL) -> String? {
        let payload = url.absoluteString
            .replacingOccurrences(of: "https://godbolt.org/clientstate/", with: "")
        guard let base64 = payload.removingPercentEncoding,
              let data = Data(base64Encoded: base64)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeClientState(from url: URL) throws -> [String: Any] {
        let json = try #require(decodedJSONString(from: url))
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }
}
