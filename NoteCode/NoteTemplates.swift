//
//  NoteTemplates.swift
//  NoteCode
//
//  Lecture, Problem and Lab: notes that start with their headings in place.
//

import Foundation
import SwiftData

/// A kind of note to start from.
///
/// **Text only**, like the Welcome note: headings, a checklist and an empty
/// code block, with no ink, so a template is just Markdown and the parser
/// that reads every note reads it. Bracketed words — `[Topic]`, `[Step]` —
/// are placeholders to type over; they aren't a link (a link needs the
/// parenthesis after it), so they show as typed.
///
/// What the reader gets is on the `InAndOut` board of the v3 canvas.
nonisolated enum NoteTemplate: String, CaseIterable, Sendable, Identifiable {
    case lecture
    case problem
    case lab

    var id: String { rawValue }

    /// The name in the menus, and the new note's title, which opens ready to
    /// rename.
    var title: String {
        switch self {
        case .lecture: "Lecture"
        case .problem: "Problem"
        case .lab:     "Lab"
        }
    }

    var systemImage: String {
        switch self {
        case .lecture: "graduationcap"
        case .problem: "puzzlepiece"
        case .lab:     "testtube.2"
        }
    }

    /// The note's text.
    ///
    /// - Parameters:
    ///   - language: tags the code block. See `NoteTemplates.commonLanguage`.
    ///   - now: the date a Lecture is dated, as "13 Oct".
    func content(language: CodeLanguage, now: Date = .now, locale: Locale = .current) -> String {
        let block = "```\(language.rawValue)\n\n```"
        switch self {
        case .lecture:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "d MMM"
            return """
            # Lecture [N] · [Topic]

            [Course] · \(formatter.string(from: now))

            ## Key ideas

            -\u{20}
            -\u{20}

            ## Code

            \(block)

            ## Questions

            -\u{20}
            """
        case .problem:
            return """
            # [Problem]

            [link](https://)

            Difficulty: [Easy]

            ## Approach

            -\u{20}

            ## Complexity

            Time O( ) · Space O( )

            \(block)

            ## Mistakes

            -\u{20}
            """
        case .lab:
            return """
            # Lab [N] · [Topic]

            ## Goal

            [One line]

            ## Steps

            - [ ] [Step]
            - [ ] [Step]

            ## Code

            \(block)

            ## Results

            """
        }
    }
}

nonisolated enum NoteTemplates {

    /// The language a template's code block is tagged with: the one used in
    /// most code blocks of `contents`, else C++.
    ///
    /// A folder is a class, and a class is mostly one language, so a Lecture
    /// made in CS133's folder starts as C++ and one made among the algorithm
    /// practice starts as Python. A tie goes to the language earlier in the
    /// menus. Blocks in no language the app knows aren't counted.
    static func commonLanguage(in contents: some Sequence<String>) -> CodeLanguage {
        var counts: [CodeLanguage: Int] = [:]
        for content in contents {
            for block in DocumentParser.parse(content) {
                if let language = block.codeBlock?.language {
                    counts[language, default: 0] += 1
                }
            }
        }
        var best = CodeLanguage.cpp
        var bestCount = 0
        for language in CodeLanguage.allCases {
            let count = counts[language] ?? 0
            if count > bestCount {
                best = language
                bestCount = count
            }
        }
        return best
    }
}

extension Page {

    /// Makes a note from a template, files it in `folder` if given, and
    /// inserts it. Through `Page.create`, so it is a note like any other:
    /// the same orientation and Markdown layout.
    @discardableResult
    static func create(
        from template: NoteTemplate,
        orientation: PageOrientation,
        in folder: Folder? = nil,
        now: Date = .now,
        context: ModelContext
    ) -> Page {
        let language = NoteTemplates.commonLanguage(in: (folder?.livePages ?? []).map(\.content))
        let page = create(orientation: orientation, in: folder, context: context)
        page.title = template.title
        page.content = template.content(language: language, now: now)
        return page
    }
}
