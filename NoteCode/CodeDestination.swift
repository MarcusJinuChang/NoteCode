//
//  CodeDestination.swift
//  NoteCode
//
//  The site a code block goes to when it can't run in the app.
//

import Foundation

// MARK: - Delivery

/// How a destination receives the code.
///
/// The distinction is the whole reason this type exists: most free online
/// compilers keep their editor contents in the browser's own storage and have
/// no way to be handed a program from outside, while a few encode the whole
/// program in the link. One tap versus one tap and a paste — worth knowing
/// about, because the UI has to say which is about to happen.
nonisolated enum CodeDelivery: Equatable, Sendable {
    /// The program travels inside the link, so it is already there on arrival.
    case inURL
    /// The site cannot be prefilled. The code goes on the pasteboard first and
    /// the student pastes it into the editor when they land.
    case pasteboard
}

// MARK: - Destination

/// A free online compiler a code block can be handed off to.
///
/// Not a choice the student makes (30 Oct): our run service runs every
/// language Run offers, so a site is only where a block goes when a run can't
/// happen — the day's runs used up, the service down, a block too big — and
/// where Run goes in a build without a service. `request(for:language:)`
/// picks it.
nonisolated enum CodeDestination: Equatable, Hashable, Sendable {
    /// programiz.com. Has every language Run offers, and an editor the code
    /// has to be pasted into: where whatever can't go in a link goes.
    case programiz
    /// godbolt.org. The only one of these that can be handed a program in a
    /// link, so a run there is genuinely one tap.
    case compilerExplorer

    // MARK: Capability

    /// The languages this destination can be sent to directly.
    ///
    /// Compiler Explorer is missing Java on purpose, and it is not an oversight
    /// about the site: its Java executor always compiles into a fixed filename,
    /// so the `public class Main` that every course teaches fails to build
    /// there with an error about the file name. Verified against the live site.
    /// Sending Java somewhere that runs it beats sending it somewhere that
    /// greets the student with a compiler error.
    ///
    /// It is missing JavaScript for a plainer reason: its only JavaScript
    /// compilers are V8 builds that show bytecode and cannot execute
    /// (`supportsExecute` is false for both, 13 Oct 2026). So JavaScript lands
    /// on Programiz.
    ///
    /// SQL is in none of them. It isn't `canRun` at all, so no request is
    /// ever made for it; see `CodeLanguage.canRun`.
    var supportedLanguages: Set<CodeLanguage> {
        let runnable = Set(CodeLanguage.allCases.filter(\.canRun))
        return switch self {
        case .programiz:        runnable
        case .compilerExplorer: [.cpp, .python, .c, .rust, .go]
        }
    }

    func supports(_ language: CodeLanguage) -> Bool {
        supportedLanguages.contains(language)
    }
}

// MARK: - Request

/// Everything the run button has to do, worked out before anything happens.
///
/// Kept as a value so the decision — which site, which link, whether the code
/// needs to go on the pasteboard — is testable without a pasteboard, a text
/// view, or a network.
nonisolated struct RunRequest: Equatable, Sendable {
    /// Where this ends up; see `CodeDestination.request(for:language:)`.
    var destination: CodeDestination
    var url: URL
    var delivery: CodeDelivery
    /// The code to put on the pasteboard before opening `url`, or `nil` when
    /// the link already carries it.
    var pasteboardCode: String?
}

extension CodeDestination {

    /// Resolves a block into the work of handing it to a site: a Compiler
    /// Explorer link where the language runs there and the code fits in one
    /// (`maximumLinkedCodeLength`), otherwise Programiz's page for the
    /// language with the code on the pasteboard. `request.destination` says
    /// which.
    static func request(for code: String, language: CodeLanguage) -> RunRequest {
        if compilerExplorer.supports(language),
           let url = compilerExplorerURL(code: code, language: language) {
            return RunRequest(destination: .compilerExplorer, url: url, delivery: .inURL, pasteboardCode: nil)
        }
        return RunRequest(
            destination: .programiz,
            url: programizPage(for: language),
            delivery: .pasteboard,
            pasteboardCode: code
        )
    }

    /// Programiz's compiler for a language, where the code is pasted.
    private static func programizPage(for language: CodeLanguage) -> URL {
        let string = switch language {
        case .cpp:        "https://www.programiz.com/cpp-programming/online-compiler/"
        case .java:       "https://www.programiz.com/java-programming/online-compiler/"
        case .python:     "https://www.programiz.com/python-programming/online-compiler/"
        case .c:          "https://www.programiz.com/c-programming/online-compiler/"
        case .javascript: "https://www.programiz.com/javascript/online-compiler/"
        case .rust:       "https://www.programiz.com/rust/online-compiler/"
        case .go:         "https://www.programiz.com/golang/online-compiler/"
        case .sql:        "https://www.programiz.com/sql/online-compiler/"
        }
        // Every string above is a literal this file controls.
        return URL(string: string) ?? URL(string: "https://www.programiz.com/")!
    }
}

// MARK: - Compiler Explorer

extension CodeDestination {

    /// Compiler Explorer reads a whole session out of the path: a JSON document
    /// describing the editor and the panes to open, base64'd. Asking for an
    /// executor rather than a compiler is what makes the student land on
    /// program output instead of on assembly.
    ///
    /// Compiler ids are pinned. They have to be — the site has 1,197 of them
    /// and no "latest" alias — so they are a maintenance item, not a constant.
    /// A retired id still shows the code, with the compiler pane complaining,
    /// which is why it isn't worth more machinery than a comment.
    private struct ClientState: Encodable {
        struct Compiler: Encodable {
            var id: String
            var libs: [String] = []
            var options: String
        }

        struct Executor: Encodable {
            var compiler: Compiler
        }

        struct Session: Encodable {
            var id = 1
            var language: String
            var source: String
            var compilers: [Compiler] = []
            var executors: [Executor]
        }

        var sessions: [Session]
    }

    /// The compiler to run a language on, and the flags to run it with.
    ///
    /// Compiler Explorer names languages exactly as `CodeLanguage.canonicalName`
    /// already does, so only the compiler is worth stating here. Verified
    /// against godbolt.org on 11 September 2026; C, Rust and Go on 13 October;
    /// all five re-checked on 23 October 2026 against the live compiler list
    /// (`/api/compilers/<language>`: every earlier pin was still there, and gcc
    /// 16.2 and Python 3.14 were out), each by compiling and running a
    /// hello-world through its API (`/api/compiler/<id>/compile` with `execute`
    /// on) and reading the output. The newest release of each, so the ids are
    /// the part that will go stale.
    private static func compilerExplorerCompiler(
        for language: CodeLanguage
    ) -> (id: String, options: String)? {
        switch language {
        case .cpp:    ("g162", "-O2 -std=c++17")
        case .python: ("python314", "")
        case .c:      ("cg162", "-O2 -std=c17")
        case .rust:   ("r1990", "-O")
        case .go:     ("gl1260", "")
        // No executor for these; see `supportedLanguages`.
        case .java, .javascript, .sql: nil
        }
    }

    /// How long a `clientstate` link is allowed to get.
    ///
    /// The program sits in the URL *path*, so it goes through everything
    /// between here and their server that has an opinion about request-line
    /// length, and 8KB is the common ceiling. A block of class notes is a
    /// fraction of this; past it the code rides the pasteboard instead, which
    /// still works and is the failure mode the student can act on.
    static let maximumLinkedCodeLength = 8_000

    static func compilerExplorerURL(code: String, language: CodeLanguage) -> URL? {
        guard let compiler = compilerExplorerCompiler(for: language) else { return nil }

        let state = ClientState(sessions: [
            ClientState.Session(
                language: language.canonicalName,
                source: code,
                executors: [
                    .init(compiler: .init(id: compiler.id, options: compiler.options))
                ]
            )
        ])

        let encoder = JSONEncoder()
        // Sorted so the same block always produces the same link — a link that
        // reshuffles itself between runs can't be asserted on in a test.
        // Slashes unescaped because code is full of them and `\/` would inflate
        // every comment and every closing tag for nothing.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        guard let json = try? encoder.encode(state) else { return nil }

        // Percent-encoding everything non-alphanumeric covers base64's `+`, `/`
        // and `=`, all three of which mean something else in a path.
        let encoded = json.base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""

        let string = "https://godbolt.org/clientstate/" + encoded
        guard string.count <= maximumLinkedCodeLength else { return nil }
        return URL(string: string)
    }
}
