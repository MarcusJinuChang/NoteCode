import UIKit

/// Momentum for the page's sideways axis (W2).
///
/// The text view's pan is on `PageView` and drives both offsets, but only the
/// text view decelerates on its own, and only vertically. This carries a
/// sideways drag on the way `UIScrollView` does: the same deceleration rate,
/// stopping when the speed is gone or the edge is reached.
@MainActor
final class SidewaysFling {

    private var link: CADisplayLink?
    private var velocity: CGFloat = 0
    private var step: ((CGFloat) -> Bool)?
    private var last: CFTimeInterval = 0

    /// Speed (points a second) under which a fling is not worth starting.
    static let minimumSpeed: CGFloat = 20

    /// The speed after `elapsed` seconds, and how far it went in them, for a
    /// start speed `v`: exponential decay at the system's normal rate.
    static func decayed(_ v: CGFloat, over elapsed: TimeInterval) -> (velocity: CGFloat, distance: CGFloat) {
        let rate = UIScrollView.DecelerationRate.normal.rawValue
        // rate^(1000 t) per second, as UIScrollView defines it per millisecond.
        let k = CGFloat(log(Double(rate)) * 1000)
        let decay = CGFloat(exp(Double(k) * elapsed))
        return (v * decay, v * (decay - 1) / k)
    }

    /// Starts a fling. `step` takes the distance to move and returns whether
    /// it moved; a fling that can't move ends.
    func start(velocity: CGFloat, step: @escaping (CGFloat) -> Bool) {
        stop()
        guard abs(velocity) > Self.minimumSpeed else { return }
        self.velocity = velocity
        self.step = step
        last = CACurrentMediaTime()
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in self?.tick() }, selector: #selector(DisplayLinkTarget.fire))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        step = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = now - last
        last = now
        let next = Self.decayed(velocity, over: elapsed)
        velocity = next.velocity
        let moved = step?(next.distance) ?? false
        if !moved || abs(velocity) < Self.minimumSpeed {
            stop()
        }
    }
}

/// Keeps the display link from retaining its owner.
private final class DisplayLinkTarget {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

/// The page's edge in the continuous modes (W2): a hairline and a soft
/// shadow, so the page reads as a sheet lying on the background. Print
/// layout's sheets carry the same (`PageDecorationView.makeSheet`).
final class PageEdgeView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = PageView.pageColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.borderWidth = 1
        resolveColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var frame: CGRect {
        didSet { layer.shadowPath = UIBezierPath(rect: bounds).cgPath }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        resolveColors()
    }

    /// CALayer colours are plain CGColors and don't follow dark mode alone.
    private func resolveColors() {
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}
