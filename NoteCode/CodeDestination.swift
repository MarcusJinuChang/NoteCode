//
//  CodeDestination.swift
//  NoteCode
//
//  Where a code block goes when the run button is tapped.
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
/// Running code in-app stays out of scope — see AGENTS.md, and the roadmap's
/// "Cut — Run button". Nothing here executes anything; the app's whole job is
/// to get the block to a toolchain the student already trusts and let them run
/// it there.
nonisolated enum CodeDestination: Equatable, Hashable, Sendable, Identifiable {
    /// programiz.com. The default, and the one most CS courses point at.
    case programiz
    /// onlinegdb.com. Closer to a real debugger, with stdin.
    case onlineGDB
    /// godbolt.org. The only one of these that can be handed a program in a
    /// link, so a run there is genuinely one tap.
    case compilerExplorer
    /// Anywhere else the student prefers — vscode.dev, a school judge, a
    /// personal Jupyter server. One URL for every language, since nothing is
    /// known about it beyond the address.
    case custom(URL)

    /// What a code block is handed to when nothing more specific is set.
    static let `default`: CodeDestination = .programiz

    /// The built-ins, in the order a picker should list them.
    static let builtIns: [CodeDestination] = [.programiz, .onlineGDB, .compilerExplorer]

    var name: String {
        switch self {
        case .programiz:        "Programiz"
        case .onlineGDB:        "OnlineGDB"
        case .compilerExplorer: "Compiler Explorer"
        case .custom(let url):  url.host() ?? url.absoluteString
        }
    }

    // MARK: Persistence

    /// A stable string for `Page.runDestination` and `UserDefaults`.
    ///
    /// Spelled out rather than derived from the case name so renaming a case
    /// can't silently orphan every note that pointed at it.
    var id: String {
        switch self {
        case .programiz:        "programiz"
        case .onlineGDB:        "onlinegdb"
        case .compilerExplorer: "godbolt"
        case .custom(let url):  "custom:" + url.absoluteString
        }
    }

    /// The inverse of `id`. `nil` for anything unrecognised, which is what lets
    /// a preference written by a newer build degrade to the default instead of
    /// taking a note's run button down with it.
    init?(id: String) {
        switch id {
        case "programiz": self = .programiz
        case "onlinegdb": self = .onlineGDB
        case "godbolt":   self = .compilerExplorer
        default:
            let prefix = "custom:"
            guard id.hasPrefix(prefix),
                  let url = URL(string: String(id.dropFirst(prefix.count))),
                  url.scheme != nil
            else { return nil }
            self = .custom(url)
        }
    }

    // MARK: Capability

    /// The languages this destination can be sent to directly.
    ///
    /// Compiler Explorer is missing Java on purpose, and it is not an oversight
    /// about the site: its Java executor always compiles into a fixed filename,
    /// so the `public class Main` that every course teaches fails to build
    /// there with an error about the file name. Verified against the live site.
    /// Sending Java somewhere that runs it beats sending it somewhere that
    /// greets the student with a compiler error.
    var supportedLanguages: Set<CodeLanguage> {
        switch self {
        case .programiz, .onlineGDB: Set(CodeLanguage.allCases)
        case .compilerExplorer:      [.cpp, .python]
        case .custom:                Set(CodeLanguage.allCases)
        }
    }

    func supports(_ language: CodeLanguage) -> Bool {
        supportedLanguages.contains(language)
    }

    /// Turns what someone typed into a destination, or `nil` if it can't be one.
    ///
    /// Nobody types a scheme, so a bare `vscode.dev` is read as `https://`
    /// rather than rejected. A string that still has no host after that isn't a
    /// site — `URL` will happily parse "hello" as a relative path, which would
    /// otherwise become a destination that silently goes nowhere.
    static func custom(fromTyped string: String) -> CodeDestination? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed

        guard let url = URL(string: withScheme),
              let host = url.host(), host.contains(".")
        else { return nil }

        return .custom(url)
    }
}

// MARK: - Request

/// Everything the run button has to do, worked out before anything happens.
///
/// Kept as a value so the decision — which site, which link, whether the code
/// needs to go on the pasteboard — is testable without a pasteboard, a text
/// view, or a network.
nonisolated struct RunRequest: Equatable, Sendable {
    /// Where this actually ends up. Not always the destination that was asked
    /// for — see `CodeDestination.request(for:language:preferring:)`.
    var destination: CodeDestination
    var url: URL
    var delivery: CodeDelivery
    /// The code to put on the pasteboard before opening `url`, or `nil` when
    /// the link already carries it.
    var pasteboardCode: String?
}

extension CodeDestination {

    /// Resolves a tap on the run button into the work to be done.
    ///
    /// One rule is worth stating plainly: a destination that can't take this
    /// language hands the block to one that can, rather than failing. A student
    /// who set Compiler Explorer for a C++ note and then pasted a Java snippet
    /// into it gets a running program, not a dead button. `request.destination`
    /// reports where it really went so the UI can say so.
    static func request(
        for code: String,
        language: CodeLanguage,
        preferring preferred: CodeDestination
    ) -> RunRequest {
        let destination = preferred.supports(language) ? preferred : .default
        return destination.request(for: code, language: language)
    }

    private func request(for code: String, language: CodeLanguage) -> RunRequest {
        if case .compilerExplorer = self,
           let url = Self.compilerExplorerURL(code: code, language: language) {
            return RunRequest(destination: self, url: url, delivery: .inURL, pasteboardCode: nil)
        }

        return RunRequest(
            destination: self,
            url: landingURL(for: language),
            delivery: .pasteboard,
            pasteboardCode: code
        )
    }

    /// The page to open when the code can't travel in the link.
    private func landingURL(for language: CodeLanguage) -> URL {
        let string = switch self {
        case .programiz:
            switch language {
            case .cpp:    "https://www.programiz.com/cpp-programming/online-compiler/"
            case .java:   "https://www.programiz.com/java-programming/online-compiler/"
            case .python: "https://www.programiz.com/python-programming/online-compiler/"
            }
        case .onlineGDB:
            switch language {
            case .cpp:    "https://www.onlinegdb.com/online_c++_compiler"
            case .java:   "https://www.onlinegdb.com/online_java_compiler"
            case .python: "https://www.onlinegdb.com/online_python_compiler"
            }
        case .compilerExplorer:
            "https://godbolt.org/"
        case .custom(let url):
            url.absoluteString
        }

        // Every string above is a literal this file controls, apart from the
        // custom case — and that one was already a URL before it was a string.
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
    /// against godbolt.org on 11 September 2026.
    private static func compilerExplorerCompiler(
        for language: CodeLanguage
    ) -> (id: String, options: String)? {
        switch language {
        case .cpp:    ("g142", "-O2 -std=c++17")
        case .python: ("python313", "")
        case .java:   nil   // see `supportedLanguages`
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

// MARK: - Preference

/// Which destination a code block actually goes to.
///
/// The levels are ordered most specific first, and resolution is just "the
/// first one that names a destination we recognise". Folders don't exist yet;
/// when they do, a folder's setting is one more element in the array rather
/// than another branch here.
nonisolated enum RunDestinationPreference {

    /// Where the app-wide default lives. The last level, and the only one that
    /// is always set.
    static let appDefaultKey = "runDestination.appDefault"

    /// - Parameter levels: the setting at each level, most specific first —
    ///   today the page, then the app-wide default. `nil` means "not set here",
    ///   which is the normal state of every level but the last.
    static func resolve(_ levels: [String?]) -> CodeDestination {
        for id in levels.compactMap({ $0 }) {
            if let destination = CodeDestination(id: id) { return destination }
        }
        return .default
    }
}
