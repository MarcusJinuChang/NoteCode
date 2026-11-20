//
//  TopLevelSpans.swift
//  NoteCodeTests
//
//  A line's inline nodes read back in the shape the parser gave them before
//  spans nested (text overhaul, phase 2): each pair at the top level as one
//  node with its content, a styled run as its two tags with the nodes between
//  them, and the text between as one node. Tests written against that shape
//  compare this, so they still say what they always said about which spans
//  a line has, and a line that doesn't nest reads exactly as it did.
//

import Foundation
@testable import NoteCode

struct TopLevelSpan: Equatable {
    enum Kind: Equatable {
        case text
        case strong
        case emphasis
        case inlineCode
        case strikethrough
        case link
        case spanOpen(SpanStyle)
        case spanClose
        case underline
        case highlight(HighlightColour)
        case math(MathStyle)

        init(_ markup: InlineMarkup) {
            switch markup {
            case .strong:            self = .strong
            case .emphasis:          self = .emphasis
            case .inlineCode:        self = .inlineCode
            case .strikethrough:     self = .strikethrough
            case .link:              self = .link
            case .styled(let style): self = .spanOpen(style)
            case .underline:         self = .underline
            case .highlight(let colour): self = .highlight(colour)
            case .math(let style):   self = .math(style)
            }
        }

        var isSpanTag: Bool {
            switch self {
            case .spanOpen, .spanClose: true
            default: false
            }
        }
    }

    var kind: Kind
    var range: Range<String.Index>
    var contentRange: Range<String.Index>

    var markerRanges: [Range<String.Index>] {
        guard kind != .text else { return [] }
        return [range.lowerBound..<contentRange.lowerBound, contentRange.upperBound..<range.upperBound].filter { !$0.isEmpty }
    }

    static func read(_ nodes: [InlineNode]) -> [TopLevelSpan] {
        var read: [TopLevelSpan] = []
        var depth = 0
        var pending: (kind: Kind, start: String.Index, contentStart: String.Index)?

        for node in nodes {
            if depth > 0 {
                switch node.kind {
                case .opening: depth += 1
                case .closing: depth -= 1
                case .text, .escape: break
                }
                if depth == 0, let open = pending {
                    read.append(TopLevelSpan(kind: open.kind, range: open.start..<node.range.upperBound, contentRange: open.contentStart..<node.range.lowerBound))
                    pending = nil
                }
                continue
            }

            switch node.kind {
            case .text where node.destination == node.range:
                read.append(TopLevelSpan(kind: .link, range: node.range, contentRange: node.range))
            case .text:
                if let last = read.last, last.kind == .text, last.range.upperBound == node.range.lowerBound {
                    read[read.count - 1].range = last.range.lowerBound..<node.range.upperBound
                    read[read.count - 1].contentRange = read[read.count - 1].range
                } else {
                    read.append(TopLevelSpan(kind: .text, range: node.range, contentRange: node.range))
                }
            case .opening(.styled(let style)):
                read.append(TopLevelSpan(kind: .spanOpen(style), range: node.range, contentRange: node.range.upperBound..<node.range.upperBound))
            case .closing(.styled):
                read.append(TopLevelSpan(kind: .spanClose, range: node.range, contentRange: node.range.lowerBound..<node.range.lowerBound))
            case .opening(let markup):
                pending = (Kind(markup), node.range.lowerBound, node.range.upperBound)
                depth = 1
            case .closing, .escape:
                break
            }
        }
        return read
    }

    static func read(_ text: String) -> [TopLevelSpan] {
        read(InlineParser.parse(text, in: text.startIndex..<text.endIndex))
    }
}

extension BlockNode {
    /// `inlines` in the shape before spans nested.
    var topLevel: [TopLevelSpan] { TopLevelSpan.read(inlines) }
}

extension MarkdownFormatting.InlineStyle {
    var topLevelKind: TopLevelSpan.Kind { TopLevelSpan.Kind(markup) }
}
