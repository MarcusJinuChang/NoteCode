//
//  NoteTypography.swift
//  NoteCode
//
//  The size a note's text is set in. A value the note's text view owns, so a
//  PDF or a thumbnail made while another note is open uses its own note's.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// A note's body size, and so every font the note is laid out in.
///
/// **Per note, never app-wide, and never Dynamic Type** (decided 12 Oct). The
/// size is part of the note's pagination: a larger body re-wraps every line
/// and moves the page breaks while ink stays where it was drawn, which is why
/// the system's text size is ignored and why changing this one asks first on
/// a note with ink. `Page.textSize` holds it; `nil` means 17, today's size.
nonisolated struct NoteTypography: Equatable, Sendable {

    /// The body sizes a note can be set to. Each is the system's body size at
    /// one Dynamic Type step (xSmall to xxxLarge), so every size keeps that
    /// step's own line spacing and its headings and code come with it.
    static let sizes = [14, 15, 16, 17, 19, 21, 23]

    /// 17, the size every note had before it could be chosen.
    static let defaultSize = 17

    /// The body size in points: one of `sizes`.
    let bodySize: Int

    /// - Parameter bodySize: a size from `sizes`; `nil` is the default. A
    ///   stored size that isn't a step (written by a later build) becomes the
    ///   nearest one, rather than a font no step has.
    init(bodySize: Int? = nil) {
        let wanted = bodySize ?? Self.defaultSize
        self.bodySize = Self.sizes.min { abs($0 - wanted) < abs($1 - wanted) } ?? Self.defaultSize
    }

    static let standard = NoteTypography()

    var isStandard: Bool { bodySize == Self.defaultSize }

    /// What to store in `Page.textSize`: `nil` for the default, so a note
    /// nobody has resized stays exactly as it was.
    var storedSize: Int? { isStandard ? nil : bodySize }

    /// The size `steps` places away, or `nil` past either end. Stepping is
    /// what + and − do, so they are disabled when this answers `nil`.
    func size(steppedBy steps: Int) -> Int? {
        guard let index = Self.sizes.firstIndex(of: bodySize) else { return nil }
        let target = index + steps
        return Self.sizes.indices.contains(target) ? Self.sizes[target] : nil
    }
}

#if canImport(UIKit)
extension NoteTypography {

    /// The Dynamic Type step whose body size this is.
    var contentSizeCategory: UIContentSizeCategory {
        switch bodySize {
        case 14: .extraSmall
        case 15: .small
        case 16: .medium
        case 19: .extraLarge
        case 21: .extraExtraLarge
        case 23: .extraExtraExtraLarge
        default: .large
        }
    }

    /// The system's font for a text style *as it is at this note's step*,
    /// leading and all: not `systemFont(ofSize:)` of the same size, which has
    /// none, so every line came out 1.7pt shorter at 17 (measured in Phase 9:
    /// body leading 1.71pt, line height 20.29 either way) and moved the page
    /// breaks of every note already written, away from its ink.
    ///
    /// Not rescaled afterwards: the text view has
    /// `adjustsFontForContentSizeCategory` off, and nothing else re-resolves a
    /// font put in the text storage.
    func font(for style: UIFont.TextStyle) -> UIFont {
        UIFont.preferredFont(
            forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        )
    }

    /// Body text.
    var prose: UIFont { font(for: .body) }

    /// Monospaced at body's size, so a line of code is as tall as a line of
    /// prose.
    var code: UIFont {
        UIFont.monospacedSystemFont(ofSize: prose.pointSize, weight: .regular)
    }

    /// Headings are bold, at the sizes the text styles have at this step.
    func heading(level: Int) -> UIFont {
        let style: UIFont.TextStyle = switch level {
        case 1:  .largeTitle
        case 2:  .title1
        case 3:  .title2
        case 4:  .title3
        case 5:  .headline
        default: .subheadline
        }
        let font = self.font(for: style)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitBold)) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// A code line's number: the code's face, a little smaller so it recedes.
    var lineNumber: UIFont {
        Self.lineNumberFont(forCodeSize: code.pointSize)
    }

    /// The same, from the size of the code the number sits beside. A
    /// fragment knows its own text's font and not the note's typography.
    static func lineNumberFont(forCodeSize size: CGFloat) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: (size * 0.85 * 2).rounded() / 2, weight: .regular)
    }
}
#endif
