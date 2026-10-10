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

    /// Called with the language picked, `nil` for plain text.
    var onChoose: ((CodeLanguage?) -> Void)?

    /// The language the block has now, so the menu can tick it.
    private var current: CodeLanguage?
    private var currentIsPlain = true

    /// Space either side of the name. The button reaches this far past the
    /// text so it is easier to hit; the overlay moves it left by the same
    /// amount, so the name lines up with the code.
    static let horizontalInset: CGFloat = 8

    static let height: CGFloat = CodeBlockActionBar.buttonSide

    /// The least a button is wide: "C++" alone is under 30pt.
    static let minimumWidth: CGFloat = 44

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
            attributes.font = .systemFont(ofSize: 13, weight: .semibold)
            return attributes
        }
        self.configuration = configuration

        // Built when the menu opens, so it ticks the language the block has
        // then rather than the one it had when the button was made.
        menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.choices() ?? [])
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
    ///   - language: the block's language, `nil` for none the app knows.
    ///   - isPlain: a bare fence, which is the menu's Plain Text.
    ///   - isEnabled: false while the note's text is locked.
    func configure(label: String, language: CodeLanguage?, isPlain: Bool, isEnabled: Bool) {
        current = language
        currentIsPlain = isPlain
        self.isEnabled = isEnabled
        if configuration?.title != label {
            configuration?.title = label
        }
        accessibilityLabel = "Language, \(label)"
        accessibilityHint = "Changes the code block's language"
    }

    /// The menu's items: the languages the app knows, then plain text.
    func choices() -> [UIAction] {
        let languages = CodeLanguage.allCases.map { language in
            UIAction(title: language.displayName, state: language == current ? .on : .off) { [weak self] _ in
                self?.onChoose?(language)
            }
        }
        let plain = UIAction(title: "Plain Text", state: currentIsPlain ? .on : .off) { [weak self] _ in
            self?.onChoose?(nil)
        }
        return languages + [plain]
    }

    /// The size the button wants for its name.
    var preferredSize: CGSize {
        let fitted = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: max(fitted.width, Self.minimumWidth), height: Self.height)
    }

    /// Where the button sits: its name starts where the code does.
    ///
    /// - Parameter lineFrame: the first line's frame, in the text view's
    ///   content coordinates.
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
