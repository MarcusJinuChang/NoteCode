//
//  CodeBlockActionBar.swift
//  NoteCode
//
//  The run and copy buttons that sit in a code block's top-right corner.
//

#if canImport(UIKit)

import UIKit

/// Two buttons in a code block's header, at its right end.
///
/// The header is the opening fence's line, which is nearly always short — a
/// fence and a language tag — so its right-hand end is free, and the buttons
/// cost the code itself no room at all. Since step 10 the header is taller
/// than a line of code (`CodeBlockRoom.headerHeight`), so they sit inside it
/// rather than overhanging the lines above and below.
final class CodeBlockActionBar: UIView {

    var onRun: (() -> Void)?
    var onCopy: (() -> Void)?

    /// Side of one square button.
    static let buttonSide: CGFloat = 32

    static let spacing: CGFloat = 4

    /// Gap between the copy button and the right edge of the panel.
    static let margin: CGFloat = 8

    static var size: CGSize {
        CGSize(width: buttonSide * 2 + spacing, height: buttonSide)
    }

    /// Size when the run button is hidden — an untagged fence has nowhere to
    /// run to, so the block gets copy alone rather than a button that can't work.
    static var copyOnlySize: CGSize {
        CGSize(width: buttonSide, height: buttonSide)
    }

    private let runButton = CodeBlockActionBar.makeButton(
        systemName: "play.fill",
        tint: .tintColor,
        label: "Run code block"
    )

    private let copyButton = CodeBlockActionBar.makeButton(
        systemName: "doc.on.doc",
        tint: .secondaryLabel,
        label: "Copy code block"
    )

    private let stack = UIStackView()

    /// Restores the copy button's icon after the tick shown on a successful copy.
    private var resetCopyIcon: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)

        stack.axis = .horizontal
        stack.spacing = Self.spacing
        stack.distribution = .fillEqually
        stack.addArrangedSubview(runButton)
        stack.addArrangedSubview(copyButton)
        addSubview(stack)

        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stack.frame = bounds
    }

    /// - Parameters:
    ///   - showsRun: false for a block whose fence carries no language the app
    ///     knows, or one it can't run (SQL), since `CodeDestination` has
    ///     nowhere to send it.
    ///   - isOutput: the block is a console, a dark panel in both
    ///     appearances, so its copy button is a light grey and not
    ///     `.secondaryLabel`, which would nearly vanish on it.
    func configure(showsRun: Bool, isOutput: Bool = false) {
        runButton.isHidden = !showsRun
        let tint: UIColor = isOutput ? CodeOutputPanel.controlColor : .secondaryLabel
        if copyTint != tint {
            copyTint = tint
            copyButton.tintColor = tint
        }
    }

    /// The copy button's resting colour, which the tick returns to.
    private var copyTint: UIColor = .secondaryLabel

    /// Confirms a copy on the button itself.
    ///
    /// Worth the few lines: copying puts nothing on screen, and without this
    /// the only way to find out whether the tap registered is to go and paste
    /// somewhere.
    func acknowledgeCopy() {
        resetCopyIcon?.cancel()
        copyButton.setImage(Self.icon("checkmark"), for: .normal)
        copyButton.tintColor = .systemGreen

        let reset = DispatchWorkItem { [weak self] in
            self?.copyButton.setImage(Self.icon("doc.on.doc"), for: .normal)
            self?.copyButton.tintColor = self?.copyTint
        }
        resetCopyIcon = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: reset)
    }

    @objc private func runTapped() { onRun?() }

    @objc private func copyTapped() { onCopy?() }

    // MARK: Building

    private static func icon(_ systemName: String) -> UIImage? {
        UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
    }

    private static func makeButton(systemName: String, tint: UIColor, label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(icon(systemName), for: .normal)
        button.tintColor = tint
        button.accessibilityLabel = label
        // The pointer lifts the button, instead of showing the text view's
        // I-beam over it.
        button.isPointerInteractionEnabled = true
        return button
    }

    // MARK: Geometry

    /// Where the bar sits, in the text view's content coordinates.
    ///
    /// Right-aligned against the panel rather than against the text, because
    /// the panel is what the student sees as the block's edge — the text on the
    /// fence line stops after the language tag. Vertically it centres on the
    /// header.
    ///
    /// - Parameters:
    ///   - panelRight: the panel's right edge. The panel spans the text
    ///     column and the room beside it, not the glyphs, so this comes from
    ///     the text container — see `CodeBlockRoom`.
    ///   - lineFrame: the block's header (`CodeBlockRoom.header`), already
    ///     moved into content coordinates.
    static func frame(size: CGSize, panelRight: CGFloat, lineFrame: CGRect) -> CGRect {
        CGRect(
            x: panelRight - margin - size.width,
            y: lineFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

#endif
