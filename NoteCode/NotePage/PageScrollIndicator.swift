#if canImport(UIKit)

import UIKit

/// What the page's scroll indicator reads from the page it sits on.
@MainActor
protocol PageScrollIndicatorHost: UIScrollView {
    var textView: DocumentUITextView { get }
    var displayScale: CGFloat { get }
}

/// The note's scroll indicator: a capsule at the page view's right edge, so it
/// runs at the window's edge, not the page's. It shows while the note moves
/// and fades after (docs/refactor/2P-page.md, 2P2).
///
/// `PageView` owns one and calls `install()` once the text view is in place.
@MainActor
final class PageScrollIndicator {
    static let width: CGFloat = 3
    static let inset: CGFloat = 3
    static let minimumLength: CGFloat = 36

    /// How long the indicator stays after it last moved, then how long it
    /// takes to fade.
    private static let hold: Duration = .seconds(0.8)
    private static let fadeOut: TimeInterval = 0.3

    private let view = UIView()
    private var offsetObservation: NSKeyValueObservation?
    private var fadeTask: Task<Void, Never>?
    private weak var host: PageScrollIndicatorHost?

    init(host: PageScrollIndicatorHost) {
        self.host = host
    }

    /// Adds the capsule to the page and starts following the text view.
    func install() {
        guard let host else { return }
        view.isUserInteractionEnabled = false
        view.alpha = 0
        host.addSubview(view)
        host.textView.addLayoutObserver { [weak self] in self?.update() }
        offsetObservation = host.textView.observe(\.contentOffset) { [weak self] _, _ in
            // KVO delivers on the thread that scrolled, which is the main one.
            MainActor.assumeIsolated { self?.moved() }
        }
    }

    /// Where the indicator sits in the page view, or nil when the note fits.
    /// `offset` and `content` are in page points; `scale` turns them to
    /// screen points.
    static func frame(
        offset: CGFloat, content: CGFloat, area: CGSize, scale: CGFloat, sideways: CGFloat
    ) -> CGRect? {
        let total = content * scale
        guard total > area.height + 0.5 else { return nil }
        let length = max(area.height * area.height / total, minimumLength)
        let travel = area.height - length
        let progress = min(max(offset * scale / (total - area.height), 0), 1)
        return CGRect(
            x: sideways + area.width - width - inset,
            y: progress * travel,
            width: width,
            height: length
        )
    }

    private func update() {
        guard let host else { return }
        view.backgroundColor = UIColor.label.withAlphaComponent(0.35)
        view.layer.cornerRadius = Self.width / 2
        // Not the keyboard's inset: the bar rides above it and the note
        // scrolls under, so the indicator runs the whole window.
        guard let frame = Self.frame(
            offset: host.textView.contentOffset.y + host.textView.contentInset.top,
            content: host.textView.contentSize.height,
            area: host.bounds.size,
            scale: host.displayScale,
            sideways: host.contentOffset.x
        ) else {
            view.isHidden = true
            return
        }
        view.isHidden = false
        view.frame = frame.offsetBy(dx: 0, dy: host.contentOffset.y)
        host.bringSubviewToFront(view)
    }

    private func moved() {
        update()
        guard !view.isHidden else { return }
        fadeTask?.cancel()
        view.layer.removeAllAnimations()
        view.alpha = 1
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.hold)
            guard !Task.isCancelled, let self else { return }
            UIView.animate(withDuration: Self.fadeOut) { self.view.alpha = 0 }
        }
    }
}

#endif
