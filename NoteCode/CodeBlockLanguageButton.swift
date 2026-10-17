//
//  CodeBlockLanguageButton.swift
//  NoteCode
//
//  The language's name on a code block's opening line, and the menu behind it.
//

#if canImport(UIKit)

import UIKit

/// What stands in for an away block's opening fence.
///
/// The fence's glyphs are not drawn (see `CodeBlockLayoutFragment.draw`), and
/// this sits where they were, left-aligned with the code. It is a button for
/// the same reason the run and copy buttons are views floating over the text:
/// a label drawn by the fragment can't take a tap. It is an action-bar
/// control, so `DocumentUITextView` keeps its own gestures off it and the
/// overlay keeps it under the ink canvas.
final class CodeBlockLanguageButton: UIButton {

    /// Called with what was picked: a language, Output or Plain Text.
    var onChoose: ((CodeBlockKind) -> Void)?

    /// What the block is now, so the menu can tick it. `nil` for a tag the
    /// app doesn't know, which ticks nothing.
    private var current: CodeBlockKind?

    /// Space either side of the name. The button reaches this far past the
    /// text so it is easier to hit; the overlay moves it left by the same
    /// amount, so the name lines up with the code.
    static let horizontalInset: CGFloat = 8

    static let height: CGFloat = CodeBlockActionBar.buttonSide

    /// The least a button is wide: "C++" alone is under 30pt.
    static let minimumWidth: CGFloat = 44

    /// The name's face, which paper draws too (`drawHeaderLabel`).
    static let titleFont = UIFont.systemFont(ofSize: 13, weight: .semibold)

    override init(frame: CGRect) {
        super.init(frame: frame)

        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Self.horizontalInset, bottom: 0, trailing: Self.horizontalInset
        )
        configuration.baseForegroundColor = .secondaryLabel
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = CodeBlockLanguageButton.titleFont
            return attributes
        }
        self.configuration = configuration
        isPointerInteractionEnabled = true

        // Built when the menu opens, so it ticks the language the block has
        // then rather than the one it had when the button was made.
        menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.groupedChoices() ?? [])
            }
        ])
        showsMenuAsPrimaryAction = true
        accessibilityTraits.insert(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameters:
    ///   - label: `CodeBlockTarget.languageLabel`.
    ///   - kind: `CodeBlockTarget.kind`.
    ///   - isOutput: draws the name in the output panel's label colour, which
    ///     is on a dark panel in both appearances.
    ///   - isEnabled: false while the note's text is locked.
    func configure(label: String, kind: CodeBlockKind?, isOutput: Bool = false, isEnabled: Bool) {
        current = kind
        self.isEnabled = isEnabled
        if configuration?.baseForegroundColor != (isOutput ? CodeOutputPanel.labelColor : .secondaryLabel) {
            configuration?.baseForegroundColor = isOutput ? CodeOutputPanel.labelColor : .secondaryLabel
        }
        if configuration?.title != label {
            configuration?.title = label
        }
        accessibilityLabel = "Language, \(label)"
        accessibilityHint = "Changes the code block's language"
    }

    /// The menu's items: the languages the app knows, then Output and plain
    /// text. The same list as the hotbar's Code Block ▾, from `CodeBlockKind.menu`.
    func choices() -> [UIAction] {
        CodeBlockKind.menu.map { kind in
            let action = UIAction(title: kind.displayName, state: kind == current ? .on : .off) { [weak self] _ in
                self?.onChoose?(kind)
            }
            action.subtitle = kind.subtitle
            return action
        }
    }

    /// The same choices with a divider between the languages and the rest.
    func groupedChoices() -> [UIMenuElement] {
        let actions = choices()
        let split = CodeBlockKind.languages.count
        return [
            UIMenu(options: .displayInline, children: Array(actions[..<split])),
            UIMenu(options: .displayInline, children: Array(actions[split...])),
        ]
    }

    /// The size the button wants for its name.
    var preferredSize: CGSize {
        let fitted = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: max(fitted.width, Self.minimumWidth), height: Self.height)
    }

    /// Where the button sits: its name starts where the code does.
    ///
    /// - Parameter lineFrame: the block's header (`CodeBlockRoom.header`), in
    ///   the text view's content coordinates.
    static func frame(size: CGSize, lineFrame: CGRect, maximumWidth: CGFloat) -> CGRect {
        CGRect(
            x: lineFrame.minX - horizontalInset,
            y: lineFrame.midY - size.height / 2,
            width: min(size.width, max(maximumWidth, minimumWidth)),
            height: size.height
        )
    }
}

#endif
