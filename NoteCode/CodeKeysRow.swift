//
//  CodeKeysRow.swift
//  NoteCode
//
//  The row of keys above the on-screen keyboard while the caret is in code.
//

#if canImport(UIKit)

import GameController
import UIKit

/// ⇥ ⇤ { } ( ) [ ] < > ; = " ' : / \ | & * #  ← →, on a bar-material capsule, in
/// the options row's look: 40pt to the eye in a row 52pt tall.
///
/// An `inputAccessoryView`, so UIKit puts it on the keyboard and the keyboard's
/// frame includes it. The symbols scroll when the row is wider than the
/// window (a narrow Split View); the indent and arrow keys stay put at the
/// two ends, since those are the ones used between two taps on the others.
///
/// A UIKit view and not a SwiftUI one hosted in it, because an accessory is
/// lifted off the view tree into the keyboard's window, and a hosting
/// controller with no parent is easy to lose there.
final class CodeKeysRow: UIInputView, UIInputViewAudioFeedback {

    /// Called with each key as it is tapped.
    var onKey: ((CodeKey) -> Void)?

    /// The options row's cell: 34pt along it, 40pt across (`OptionsRowStyle`).
    static let keyWidth: CGFloat = 34
    static let keyHeight: CGFloat = 40
    /// The row as the keyboard sees it: the capsule and 6pt around it.
    static let height: CGFloat = 52

    var enableInputClicksWhenVisible: Bool { true }

    private let capsule = UIVisualEffectView(effect: nil)

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: CGRect(x: 0, y: 0, width: frame.width, height: Self.height), inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
        build()
    }

    convenience init() {
        self.init(frame: .zero, inputViewStyle: .keyboard)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height)
    }

    // MARK: Building

    private func build() {
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.cornerConfiguration = .capsule()
        capsule.backgroundColor = BarMaterial.uiColor
        capsule.layer.borderWidth = 0.5
        capsule.layer.borderColor = BarMaterial.uiEdge.cgColor
        addSubview(capsule)

        let leading = keyStack([.indent, .outdent])
        let trailing = keyStack([.left, .right])
        let symbols = keyStack(CodeKey.symbols)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        scroll.addSubview(symbols)

        let row = UIStackView(arrangedSubviews: [leading, divider(), scroll, divider(), trailing])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 4
        capsule.contentView.addSubview(row)

        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            capsule.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            capsule.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsule.heightAnchor.constraint(equalToConstant: 40),

            row.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),

            symbols.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            symbols.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            symbols.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            symbols.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            symbols.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: Self.keyHeight),
        ])

        // The symbols take what is left; the ends keep their size. When the
        // symbols fit, the scroll view is as wide as they are and the arrows
        // sit against them rather than at the far edge.
        let fit = scroll.widthAnchor.constraint(equalTo: scroll.contentLayoutGuide.widthAnchor)
        fit.priority = .defaultHigh
        fit.isActive = true
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for view in [leading, trailing] {
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
            view.setContentHuggingPriority(.required, for: .horizontal)
        }
    }

    private func keyStack(_ keys: [CodeKey]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: keys.map(button(for:)))
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        return stack
    }

    private func divider() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return view
    }

    /// The control a key is: a plain button in the row's monospaced face, a
    /// cell wide, with the pointer lifting it.
    func button(for key: CodeKey) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = key.title
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
            return attributes
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            UIDevice.current.playInputClick()
            self?.onKey?(key)
        })
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = key.accessibilityLabel
        button.isPointerInteractionEnabled = true
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.keyWidth),
            button.heightAnchor.constraint(equalToConstant: Self.keyHeight),
        ])
        return button
    }

    /// The keys on the row, in order. For tests.
    var buttons: [UIButton] {
        func collect(_ view: UIView) -> [UIButton] {
            view.subviews.flatMap { ($0 as? UIButton).map { [$0] } ?? collect($0) }
        }
        return collect(self)
    }
}

// MARK: - Hardware keyboard

/// Whether a physical keyboard is attached, and when that changes.
///
/// `GCKeyboard.coalesced` is the system's own answer: non-nil while any
/// keyboard is connected, the Magic Keyboard and the Smart Keyboard Folio
/// included. The on-screen keyboard's hiding is *not* the signal: an iPad with
/// a hardware keyboard shows the on-screen one on request, and a
/// reader may have hidden it with none attached.
@MainActor
enum HardwareKeyboard {

    /// Replaceable, so a test can attach and remove one.
    static var isConnected: () -> Bool = { GCKeyboard.coalesced != nil }

    /// Calls `change` each time a keyboard connects or disconnects.
    static func observe(_ change: @escaping @MainActor () -> Void) -> [NSObjectProtocol] {
        [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { change() }
            }
        }
    }
}

#endif
