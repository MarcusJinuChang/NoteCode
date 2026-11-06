#if canImport(UIKit)

import SwiftUI
import UIKit

/// What the keyboard inset, and the page's move with the hotbar, read from the
/// page they work for.
@MainActor
protocol PageKeyboardInsetHost: UIScrollView {
    var textView: DocumentUITextView { get }
    var displayScale: CGFloat { get }
}

/// The room the page keeps for the keyboard and the hotbar, and the page's
/// move when the hotbar changes the area it has (docs/refactor/2P-page.md,
/// 2P2). The page is never resized for the keyboard: this insets the text
/// view by what the keyboard covers, moving with the keyboard's own animation.
@MainActor
final class PageKeyboardInset {
    private weak var host: PageKeyboardInsetHost?

    init(host: PageKeyboardInsetHost) {
        self.host = host
    }

    /// Starts listening for the keyboard.
    func install() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    // MARK: Keyboard

    /// The keyboard's last frame, in screen coordinates.
    private var keyboardFrame: CGRect?

    /// Brings a screen-coordinates frame into a window's. Replaceable because
    /// a window made outside a scene, as in a test, has no screen space to
    /// convert from and answers with a zero rect.
    var windowFrameForScreenFrame: (CGRect, UIWindow) -> CGRect = { frame, window in
        window.convert(frame, from: window.screen.coordinateSpace)
    }

    /// Room to leave above the keyboard, in screen points: the hotbar's, when
    /// it is docked at the bottom, since it rides up with the keyboard over
    /// the page.
    var keyboardClearance: CGFloat = 0 {
        didSet {
            guard keyboardClearance != oldValue else { return }
            applyKeyboardInset(duration: 0.25)
        }
    }

    /// Room the bottom of the text keeps from the area's edge, in screen
    /// points, for a hotbar floating over the bottom of the page: the end of
    /// the note can then be scrolled out from under it. The keyboard's inset
    /// already includes the bar's height, so the larger of the two applies,
    /// not their sum.
    var restingClearance: CGFloat = 0 {
        didSet {
            guard restingClearance != oldValue else { return }
            applyKeyboardInset(duration: 0.25)
        }
    }

    /// The page moved to a window: a clearance set before it had one, as it
    /// is when made, applies now.
    func pageDidMoveToWindow() {
        if host?.window != nil, restingClearance > 0 {
            applyKeyboardInset(duration: 0)
        }
    }

    /// The page's scale changed: the resting clearance is in screen points.
    func displayScaleChanged() {
        if restingClearance > 0 {
            applyKeyboardInset(duration: 0)
        }
    }

    /// Keeps the caret clear of the keyboard without resizing the page.
    ///
    /// Fires for showing, hiding, and the keyboard changing height (the
    /// shortcut bar, the emoji keyboard, undocking). The inset moves with the
    /// keyboard's own animation.
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let end = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        keyboardFrame = end

        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 7
        applyKeyboardInset(duration: duration, options: UIView.AnimationOptions(rawValue: UInt(curve) << 16))
    }

    /// Insets the text view for whatever of the page the keyboard covers.
    private func applyKeyboardInset(duration: TimeInterval, options: UIView.AnimationOptions = []) {
        guard let host, let window = host.window else { return }
        let textView = host.textView
        let displayScale = host.displayScale

        var inset = displayScale > 0 ? restingClearance / displayScale : 0
        if let keyboardFrame {
            inset = max(inset, CanvasGeometry.keyboardInset(
                keyboard: windowFrameForScreenFrame(keyboardFrame, window),
                area: host.convert(host.bounds, to: window),
                screenWidth: window.bounds.width,
                displayScale: displayScale,
                clearance: keyboardClearance
            ))
        }
        guard textView.contentInset.bottom != inset else { return }
        let growing = inset > textView.contentInset.bottom

        UIView.animate(withDuration: duration, delay: 0, options: options.union(.beginFromCurrentState)) {
            textView.contentInset.bottom = inset
            textView.verticalScrollIndicatorInsets.bottom = inset
        }

        // A keyboard coming up over the line being typed on: bring it back
        // into view, as a text view that insets itself would.
        if growing, textView.isFirstResponder {
            textView.scrollRangeToVisible(textView.selectedRange)
        }
    }

    // MARK: Moving with the hotbar

    /// The space SwiftUI gives the page, as the edges it leaves: the strip a
    /// hotbar docked at a side takes. Only compared, to know the area is
    /// about to change: SwiftUI lays the area out.
    private(set) var areaInsets = UIEdgeInsets.zero

    /// The animation the next change of area moves the page with.
    private var areaMotion: Animation?

    /// Where the page was on screen after the last layout pass: the text
    /// view's centre in window coordinates, its scale and its size.
    var lastPlaceOnScreen: (center: CGPoint, scale: CGFloat, size: CGSize)?

    /// The page's area is about to become `insets` less than the window, and
    /// the page should get there with `animation`.
    ///
    /// SwiftUI lays a UIKit view out where it ends up, at once: it resized
    /// this view, or moved a container above it, while the hotbar slid to its
    /// new edge with `.snappy`, so the page jumped. This is called before
    /// SwiftUI lays out the new area (logged, 17 Oct), and the page hears of
    /// a move only through here (a move without a resize lays nothing out),
    /// so it lays out again and animates the page from where it was on
    /// screen (`PageView.layoutSubviews`). Nothing under Reduce Motion.
    func areaWillChange(to insets: UIEdgeInsets, animation: Animation?) {
        guard insets != areaInsets else { return }
        areaInsets = insets
        guard let animation, !UIAccessibility.isReduceMotionEnabled, lastPlaceOnScreen != nil else { return }
        areaMotion = animation
        host?.setNeedsLayout()
    }

    /// The motion this layout pass should carry the page with, taken once.
    func takeAreaMotion() -> Animation? {
        defer { areaMotion = nil }
        return areaMotion
    }

    /// Puts the page back where it was on screen, at its old scale, and
    /// animates it to where this layout pass put it.
    ///
    /// The view stops clipping while it moves: the page starts partly outside
    /// its new area and slides in, which clipped would have lost a strip of
    /// it at once.
    func movePage(from old: (center: CGPoint, scale: CGFloat, size: CGSize), with animation: Animation) {
        guard let host, host.window != nil else { return }
        let textView = host.textView
        let start = host.convert(old.center, from: nil)
        let end = (transform: textView.transform, size: textView.bounds.size, center: textView.center)
        guard abs(start.x - end.center.x) > 0.5 || abs(start.y - end.center.y) > 0.5 || old.scale != host.displayScale
        else { return }

        UIView.performWithoutAnimation {
            textView.transform = CGAffineTransform(scaleX: old.scale, y: old.scale)
            textView.bounds.size = old.size
            textView.center = start
        }
        host.clipsToBounds = false
        UIView.animate(animation) {
            textView.transform = end.transform
            textView.bounds.size = end.size
            textView.center = end.center
        } completion: {
            host.clipsToBounds = true
        }
    }
}

#endif
