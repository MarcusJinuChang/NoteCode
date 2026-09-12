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

    @Test("A destination that runs the language keeps the block")
    func preferredDestinationIsUsed() {
        let request = CodeDestination.request(
            for: "print(1)",
            language: .python,
            preferring: .onlineGDB
        )

        #expect(request.destination == .onlineGDB)
    }

    /// The rule that stops a mismatched preference from producing a dead button.
    @Test("A destination that can't run the language hands it on")
    func unsupportedLanguageFallsBack() {
        let request = CodeDestination.request(
            for: "class A {}",
            language: .java,
            preferring: .compilerExplorer
        )

        #expect(request.destination == .default)
        #expect(request.url.host() == "www.programiz.com")
    }

    @Test("Compiler Explorer is the one that can't take Java")
    func compilerExplorerLanguages() {
        #expect(CodeDestination.compilerExplorer.supports(.cpp))
        #expect(CodeDestination.compilerExplorer.supports(.python))
        #expect(!CodeDestination.compilerExplorer.supports(.java))
    }

    @Test("The sites that take a paste take every language")
    func pasteboardDestinationsTakeEverything() {
        for destination in [CodeDestination.programiz, .onlineGDB] {
            for language in CodeLanguage.allCases {
                #expect(destination.supports(language), "\(destination.id) / \(language)")
            }
        }
    }

    // MARK: Delivery

    @Test("Programiz cannot be prefilled, so the code rides the pasteboard")
    func programizUsesPasteboard() {
        let request = CodeDestination.request(
            for: "int main() {}",
            language: .cpp,
            preferring: .programiz
        )

        #expect(request.delivery == .pasteboard)
        #expect(request.pasteboardCode == "int main() {}")
    }

    @Test("Compiler Explorer carries the code, so nothing is copied")
    func compilerExplorerUsesTheLink() {
        let request = CodeDestination.request(
            for: "int main() {}",
            language: .cpp,
            preferring: .compilerExplorer
        )

        #expect(request.delivery == .inURL)
        #expect(request.pasteboardCode == nil)
    }

    /// Exact addresses on purpose. The failure this guards against is a
    /// student landing on a C++ compiler holding Python, and only the whole
    /// path distinguishes those — "contains the language" passes for both.
    @Test("Each language lands on its own compiler page")
    func languageSpecificLandingPages() {
        let expected: [CodeLanguage: (programiz: String, gdb: String)] = [
            .cpp: (
                "https://www.programiz.com/cpp-programming/online-compiler/",
                "https://www.onlinegdb.com/online_c++_compiler"
            ),
            .java: (
                "https://www.programiz.com/java-programming/online-compiler/",
                "https://www.onlinegdb.com/online_java_compiler"
            ),
            .python: (
                "https://www.programiz.com/python-programming/online-compiler/",
                "https://www.onlinegdb.com/online_python_compiler"
            ),
        ]

        for language in CodeLanguage.allCases {
            let pages = expected[language]!
            let programiz = CodeDestination.request(for: "x", language: language, preferring: .programiz)
            let gdb = CodeDestination.request(for: "x", language: language, preferring: .onlineGDB)

            #expect(programiz.url.absoluteString == pages.programiz)
            #expect(gdb.url.absoluteString == pages.gdb)
        }
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
    @Test("A block too long for a link falls back to the pasteboard")
    func oversizedCodeFallsBack() {
        let huge = String(repeating: "int aVeryLongVariableName = 0;\n", count: 500)

        #expect(CodeDestination.compilerExplorerURL(code: huge, language: .cpp) == nil)

        let request = CodeDestination.request(for: huge, language: .cpp, preferring: .compilerExplorer)
        #expect(request.delivery == .pasteboard)
        #expect(request.pasteboardCode == huge)
        #expect(request.destination == .compilerExplorer)
    }

    @Test("A block that just fits still travels in the link")
    func sizedCodeStillLinks() {
        let sized = String(repeating: "x = 1\n", count: 200)
        let url = CodeDestination.compilerExplorerURL(code: sized, language: .python)

        #expect(url != nil)
        #expect((url?.absoluteString.count ?? .max) <= CodeDestination.maximumLinkedCodeLength)
    }

    // MARK: Custom sites

    @Test("A site typed without a scheme is still a site")
    func typedSiteGetsAScheme() {
        let destination = CodeDestination.custom(fromTyped: "  vscode.dev  ")
        #expect(destination == .custom(URL(string: "https://vscode.dev")!))
    }

    @Test("An explicit scheme is left alone")
    func typedSiteKeepsItsScheme() {
        #expect(
            CodeDestination.custom(fromTyped: "http://localhost.localdomain:8888/lab")
            == .custom(URL(string: "http://localhost.localdomain:8888/lab")!)
        )
    }

    @Test("Something that isn't an address is rejected", arguments: ["", "   ", "hello", "not a url"])
    func nonAddressesAreRejected(typed: String) {
        #expect(CodeDestination.custom(fromTyped: typed) == nil)
    }

    @Test("A custom site takes every language and always wants a paste")
    func customSiteBehaviour() throws {
        let custom = try #require(CodeDestination.custom(fromTyped: "vscode.dev"))
        let request = CodeDestination.request(for: "x = 1", language: .python, preferring: custom)

        #expect(request.destination == custom)
        #expect(request.delivery == .pasteboard)
        #expect(request.url.absoluteString == "https://vscode.dev")
    }

    @Test("A custom site is named after its host, not its whole address")
    func customSiteName() throws {
        let custom = try #require(CodeDestination.custom(fromTyped: "vscode.dev/editor/x"))
        #expect(custom.name == "vscode.dev")
    }

    // MARK: Persistence

    @Test("Every destination survives a round trip through its id")
    func idRoundTrips() throws {
        let custom = try #require(CodeDestination.custom(fromTyped: "vscode.dev"))

        for destination in CodeDestination.builtIns + [custom] {
            #expect(CodeDestination(id: destination.id) == destination, "\(destination.id)")
        }
    }

    /// The reason `init?(id:)` is failable rather than defaulting: a stored
    /// preference a future build wrote should fall back, and `resolve` is the
    /// one place that decides what to fall back *to*.
    @Test("An unrecognised id is not a destination", arguments: ["", "replit", "custom:", "custom:nope"])
    func unknownIDsAreRejected(id: String) {
        #expect(CodeDestination(id: id) == nil)
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

// MARK: - Levels

@Suite("Choosing which destination a page uses")
struct RunDestinationPreferenceTests {

    @Test("Nothing set anywhere means the default")
    func emptyResolvesToDefault() {
        #expect(RunDestinationPreference.resolve([]) == .default)
        #expect(RunDestinationPreference.resolve([nil, nil]) == .default)
    }

    @Test("The page wins over the app-wide setting")
    func pageBeatsAppDefault() {
        let resolved = RunDestinationPreference.resolve(["godbolt", "onlinegdb"])
        #expect(resolved == .compilerExplorer)
    }

    @Test("A page that hasn't chosen follows the app-wide setting")
    func unsetPageFollowsAppDefault() {
        #expect(RunDestinationPreference.resolve([nil, "onlinegdb"]) == .onlineGDB)
    }

    /// Folders don't exist yet. The point of the array is that adding that
    /// level is adding an element, not another branch — so the ordering has to
    /// hold for three levels before there are three.
    @Test("A middle level is used only when the one above it is unset")
    func middleLevelFillsIn() {
        #expect(RunDestinationPreference.resolve([nil, "godbolt", "onlinegdb"]) == .compilerExplorer)
        #expect(RunDestinationPreference.resolve(["programiz", "godbolt", nil]) == .programiz)
    }

    @Test("An id nothing recognises is skipped rather than obeyed")
    func unknownIDsAreSkipped() {
        #expect(RunDestinationPreference.resolve(["from-a-newer-build", "onlinegdb"]) == .onlineGDB)
        #expect(RunDestinationPreference.resolve(["from-a-newer-build"]) == .default)
    }
}
