import SwiftUI
import UIKit

/// Non-generic bridge for UIKit target/action and delegate callbacks.
@MainActor
final class GestureBridge: NSObject, UIGestureRecognizerDelegate {
    var onAction: (UIGestureRecognizer) -> Void = { _ in }
    var shouldReceive: (UIGestureRecognizer, UITouch) -> Bool = { _, _ in false }
    var shouldBegin: (UIGestureRecognizer) -> Bool = { _ in false }
    var scrollPan: () -> UIGestureRecognizer? = { nil }
    var longPress: UIGestureRecognizer?

    @objc func handle(_ gr: UIGestureRecognizer) { onAction(gr) }

    func gestureRecognizer(_ gr: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        shouldReceive(gr, touch)
    }

    func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool { shouldBegin(gr) }

    // The list's own pan waits for the edge strip / swipe-across to decide.
    func gestureRecognizer(_ gr: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        gr !== longPress && other === scrollPan()
    }

    // Until the hold completes, the list scrolls as usual.
    func gestureRecognizer(_ gr: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gr === longPress
    }
}

/// Drives the gesture: hit-testing, range bookkeeping, auto-scroll.
@MainActor
final class SwipeSelectEngine<ID: Hashable>: ObservableObject {
    struct Config {
        var controller: SwipeSelectController<ID>
        var count: Int
        var id: (Int) -> ID?
        var activation: [SwipeSelectActivation]
        var autoScroll: SwipeSelectAutoScroll
        var isEnabled: Bool
        var isSelectable: ((Int) -> Bool)?
        var onDragStart: ((SwipeSelectEvent<ID>) -> Void)?
        var onItemEnter: ((SwipeSelectEvent<ID>) -> Void)?
        var onDragEnd: ((SwipeSelectEvent<ID>) -> Void)?
        var isRightToLeft: Bool
    }

    let registry = SwipeSelectRegistry()
    var config: Config?
    /// The view with the SwiftUI frame of the list: finger positions are measured in it.
    weak var frameView: UIView?

    private let bridge = GestureBridge()
    private lazy var edgePan = UIPanGestureRecognizer(target: bridge, action: #selector(GestureBridge.handle))
    private lazy var acrossPan = UIPanGestureRecognizer(target: bridge, action: #selector(GestureBridge.handle))
    private lazy var longPress = UILongPressGestureRecognizer(target: bridge, action: #selector(GestureBridge.handle))
    private weak var scrollView: UIScrollView?

    // Gesture state
    private var anchor: Int?
    private var initial: Set<ID> = []
    private var shouldSelect = true
    private var range: IndexRange?
    private var lastIndex: Int?
    private var finger: CGPoint = .zero // in frameView coordinates
    private var horizontal = false
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var direction = 0

    init() {
        for gr in [edgePan, acrossPan, longPress] as [UIGestureRecognizer] {
            gr.delegate = bridge
        }
        edgePan.maximumNumberOfTouches = 1
        acrossPan.maximumNumberOfTouches = 1
        bridge.longPress = longPress
        bridge.scrollPan = { [weak self] in self?.scrollView?.panGestureRecognizer }
        bridge.onAction = { [weak self] in self?.handle($0) }
        bridge.shouldReceive = { [weak self] gr, touch in self?.shouldReceive(gr, touch) ?? false }
        bridge.shouldBegin = { [weak self] gr in self?.shouldBegin(gr) ?? false }
    }

    func attach(_ sv: UIScrollView) {
        guard sv !== scrollView else { return }
        detach()
        scrollView = sv
        registry.scrollView = sv
        sv.addGestureRecognizer(edgePan)
        sv.addGestureRecognizer(acrossPan)
        sv.addGestureRecognizer(longPress)
    }

    func detach() {
        endDrag()
        for gr in [edgePan, acrossPan, longPress] as [UIGestureRecognizer] {
            gr.view?.removeGestureRecognizer(gr)
        }
        scrollView = nil
    }

    // MARK: - Activation

    private func available(_ a: SwipeSelectActivation) -> Bool {
        guard let c = config else { return false }
        switch a.when {
        case .always: return true
        case .selectionMode: return c.controller.isSelectionMode
        case .idle: return !c.controller.isSelectionMode
        }
    }

    private func firstAvailable(where match: (SwipeSelectActivation) -> Bool) -> SwipeSelectActivation? {
        config?.activation.first { match($0) && available($0) }
    }

    private var isHorizontalList: Bool {
        guard let sv = scrollView else { return false }
        let h = sv.contentSize.width > sv.bounds.width + 1
        let v = sv.contentSize.height > sv.bounds.height + 1
        return h && !v
    }

    private func inStrip(_ p: CGPoint, side: EdgeSide, width: CGFloat) -> Bool {
        guard let fv = frameView, let c = config else { return false }
        let size = fv.bounds.size
        if isHorizontalList {
            return side == .leading ? p.y <= width : p.y >= size.height - width
        }
        let leading = (side == .leading) != c.isRightToLeft
        return leading ? p.x <= width : p.x >= size.width - width
    }

    private func shouldReceive(_ gr: UIGestureRecognizer, _ touch: UITouch) -> Bool {
        guard let c = config, c.isEnabled, c.count > 0, let fv = frameView, displayLink == nil else { return false }
        let p = touch.location(in: fv)
        guard fv.bounds.contains(p) else { return false }
        if gr === edgePan {
            return firstAvailable {
                if case let .edge(side, width, _) = $0 { return inStrip(p, side: side, width: width) }
                return false
            } != nil
        }
        let onItem = registry.hitTest(content(p), exact: true) != nil
        if gr === longPress {
            guard onItem, let a = firstAvailable(where: { if case .longPress = $0 { return true }; return false }) else { return false }
            if case let .longPress(duration, _) = a { longPress.minimumPressDuration = duration }
            return true
        }
        if gr === acrossPan {
            return onItem && firstAvailable { if case .pan = $0 { return true }; return false } != nil
        }
        return false
    }

    private func shouldBegin(_ gr: UIGestureRecognizer) -> Bool {
        if gr === acrossPan, let sv = scrollView {
            let t = acrossPan.translation(in: sv)
            return isHorizontalList ? abs(t.y) > abs(t.x) : abs(t.x) > abs(t.y)
        }
        return true
    }

    // MARK: - Gesture

    private func content(_ p: CGPoint) -> CGPoint {
        let o = scrollView?.contentOffset ?? .zero
        return CGPoint(x: p.x + o.x, y: p.y + o.y)
    }

    private func handle(_ gr: UIGestureRecognizer) {
        guard let fv = frameView else { return }
        let p = gr.location(in: fv)
        switch gr.state {
        case .began:
            var start = p
            if let pan = gr as? UIPanGestureRecognizer {
                let t = pan.translation(in: fv)
                start = CGPoint(x: p.x - t.x, y: p.y - t.y)
            }
            if !beginDrag(at: start, current: p, cancelScroll: gr === longPress) { cancel(gr) }
        case .changed:
            finger = p
            process()
        case .ended, .cancelled, .failed:
            endDrag()
        default:
            break
        }
    }

    private func cancel(_ gr: UIGestureRecognizer) {
        gr.isEnabled = false
        gr.isEnabled = true
    }

    private func beginDrag(at start: CGPoint, current: CGPoint, cancelScroll: Bool) -> Bool {
        guard let c = config, let index = registry.hitTest(content(start)), let key = c.id(index),
              c.isSelectable?(index) != false else { return false }
        if cancelScroll, let pan = scrollView?.panGestureRecognizer {
            pan.isEnabled = false
            pan.isEnabled = true
        }
        horizontal = isHorizontalList
        initial = c.controller.selected
        shouldSelect = !initial.contains(key)
        anchor = index
        range = nil
        lastIndex = nil
        finger = current
        c.controller.gestureBegan()
        enter(start: index)
        c.onDragStart?(event(index: index, key: key))
        process()
        startTicker()
        return true
    }

    private func event(index: Int, key: ID) -> SwipeSelectEvent<ID> {
        SwipeSelectEvent(index: index, id: key, mode: shouldSelect ? .select : .deselect, selected: config?.controller.selected ?? [])
    }

    /// Applies the range `[anchor ... index]`.
    private func enter(start index: Int) {
        guard let c = config, let anchor else { return }
        let clamped = max(0, min(c.count - 1, index))
        guard clamped != lastIndex else { return }
        lastIndex = clamped
        let next = IndexRange(anchor, clamped)
        if let changed = applyRangeTransition(initial: initial, current: c.controller.selected, previous: range,
                                              next: next, shouldSelect: shouldSelect, id: c.id, isSelectable: c.isSelectable) {
            c.controller.gestureUpdate(changed)
        }
        range = next
    }

    private func process() {
        guard let c = config, anchor != nil, let index = registry.hitTest(content(finger)) else { return }
        let before = lastIndex
        enter(start: index)
        if let i = lastIndex, i != before, let key = c.id(i) {
            c.onItemEnter?(event(index: i, key: key))
        }
    }

    private func endDrag() {
        stopTicker()
        guard let c = config, anchor != nil else { return }
        let i = lastIndex ?? anchor!
        anchor = nil
        range = nil
        c.controller.gestureEnded(initial: initial)
        if let key = c.id(i) { c.onDragEnd?(event(index: i, key: key)) }
        initial = []
    }

    // MARK: - Auto-scroll

    private func startTicker() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: TickerTarget { [weak self] link in self?.tick(link) }, selector: #selector(TickerTarget.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTick = 0
    }

    private func stopTicker() {
        displayLink?.invalidate()
        displayLink = nil
        setDirection(0)
    }

    private func setDirection(_ d: Int) {
        guard d != direction else { return }
        direction = d
        config?.controller.setAutoScrollDirection(d)
    }

    private func tick(_ link: CADisplayLink) {
        let dt = lastTick == 0 ? 1.0 / 60 : min(link.timestamp - lastTick, 1.0 / 30)
        lastTick = link.timestamp
        guard let c = config, c.autoScroll.isEnabled, let sv = scrollView, let fv = frameView else { return }
        let a = c.autoScroll
        let pos = horizontal ? finger.x : finger.y
        let size = horizontal ? fv.bounds.width : fv.bounds.height
        let zone = min(a.edgeSize, size / 3)
        var speed: CGFloat = 0
        if pos < zone {
            speed = -(a.minSpeed + (a.maxSpeed - a.minSpeed) * min(1, (zone - pos) / zone))
        } else if pos > size - zone {
            speed = a.minSpeed + (a.maxSpeed - a.minSpeed) * min(1, (pos - (size - zone)) / zone)
        }
        let inset = sv.adjustedContentInset
        var o = sv.contentOffset
        let minO = horizontal ? -inset.left : -inset.top
        let maxO = horizontal
            ? max(minO, sv.contentSize.width - sv.bounds.width + inset.right)
            : max(minO, sv.contentSize.height - sv.bounds.height + inset.bottom)
        let current = horizontal ? o.x : o.y
        let next = max(minO, min(maxO, current + speed * CGFloat(dt)))
        if abs(next - current) < 0.01 {
            setDirection(0)
            return
        }
        setDirection(speed > 0 ? 1 : -1)
        if horizontal { o.x = next } else { o.y = next }
        sv.setContentOffset(o, animated: false)
        process()
    }
}

/// CADisplayLink retains its target; this keeps the engine out of the cycle.
private final class TickerTarget: NSObject {
    let body: (CADisplayLink) -> Void
    init(_ body: @escaping (CADisplayLink) -> Void) { self.body = body }
    @objc func tick(_ link: CADisplayLink) { body(link) }
}
