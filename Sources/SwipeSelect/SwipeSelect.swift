import SwiftUI
import UIKit

extension View {
    /// Adds swipe-to-select to a `ScrollView` (with `LazyVStack`, `LazyVGrid`, …) or a `List`.
    ///
    /// Mark every item with ``SwiftUI/View/swipeSelectItem(_:)``.
    ///
    /// ```swift
    /// ScrollView {
    ///     LazyVStack {
    ///         ForEach(Array(mails.enumerated()), id: \.element.id) { i, mail in
    ///             MailRow(mail, selected: controller.isSelected(mail.id))
    ///                 .swipeSelectItem(i)
    ///         }
    ///     }
    /// }
    /// .swipeSelect(controller, count: mails.count, id: { mails[$0].id })
    /// ```
    ///
    /// - Parameters:
    ///   - controller: holds the selection.
    ///   - count: number of items.
    ///   - id: stable id of the item at an index. The selection holds ids, so it survives sorting and pagination.
    ///   - activation: how the gesture starts. Default: the edge strip in selection mode.
    ///   - autoScroll: auto-scroll near the edges.
    ///   - isEnabled: turn the gesture off.
    ///   - isSelectable: non-selectable items are skipped.
    public func swipeSelect<ID: Hashable>(
        _ controller: SwipeSelectController<ID>,
        count: Int,
        id: @escaping (Int) -> ID?,
        activation: [SwipeSelectActivation] = [.edge()],
        autoScroll: SwipeSelectAutoScroll = SwipeSelectAutoScroll(),
        isEnabled: Bool = true,
        isSelectable: ((Int) -> Bool)? = nil,
        onDragStart: ((SwipeSelectEvent<ID>) -> Void)? = nil,
        onItemEnter: ((SwipeSelectEvent<ID>) -> Void)? = nil,
        onDragEnd: ((SwipeSelectEvent<ID>) -> Void)? = nil
    ) -> some View {
        modifier(SwipeSelectModifier(config: { rtl in
            SwipeSelectEngine<ID>.Config(
                controller: controller, count: count, id: id, activation: activation, autoScroll: autoScroll,
                isEnabled: isEnabled, isSelectable: isSelectable, onDragStart: onDragStart,
                onItemEnter: onItemEnter, onDragEnd: onDragEnd, isRightToLeft: rtl)
        }))
    }
}

struct SwipeSelectModifier<ID: Hashable>: ViewModifier {
    let config: (Bool) -> SwipeSelectEngine<ID>.Config
    @StateObject private var engine = SwipeSelectEngine<ID>()
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        engine.config = config(layoutDirection == .rightToLeft)
        return content
            .environment(\.swipeSelectRegistry, engine.registry)
            .coordinateSpace(name: engine.registry.space)
            .background(ScrollViewProbe(onFound: { [weak engine] sv, frameView in
                engine?.frameView = frameView
                engine?.attach(sv)
            }))
            .onDisappear { engine.detach() }
    }
}

/// An invisible view with the frame of the list. Finds the `UIScrollView` behind it.
private struct ScrollViewProbe: UIViewRepresentable {
    let onFound: (UIScrollView, UIView) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.isUserInteractionEnabled = false
        v.onFound = onFound
        return v
    }

    func updateUIView(_ v: ProbeView, context: Context) {
        v.onFound = onFound
        v.setNeedsLayout()
    }
}

private final class ProbeView: UIView {
    var onFound: ((UIScrollView, UIView) -> Void)?
    private weak var found: UIScrollView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolve()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolve()
    }

    private func resolve() {
        guard window != nil else { return }
        if let sv = found, sv.window != nil {
            onFound?(sv, self)
            return
        }
        if let sv = findScrollView() {
            found = sv
            onFound?(sv, self)
        } else {
            // SwiftUI may not have built the list yet.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.found == nil, self.window != nil else { return }
                if let sv = self.findScrollView() {
                    self.found = sv
                    self.onFound?(sv, self)
                }
            }
        }
    }

    /// The smallest scroll view around our frame. Scroll views may extend under the
    /// bars, so "contains" rather than "equals".
    private func findScrollView() -> UIScrollView? {
        let target = convert(bounds, to: nil).insetBy(dx: 1, dy: 1)
        guard target.width > 0, target.height > 0 else { return nil }
        var best: UIScrollView?
        var bestArea = CGFloat.infinity
        func visit(_ v: UIView, depth: Int) {
            if v === self || depth > 40 { return }
            if let sv = v as? UIScrollView, sv.window != nil {
                let f = sv.convert(sv.bounds, to: nil)
                if f.contains(target) {
                    let area = f.width * f.height
                    if area < bestArea {
                        best = sv
                        bestArea = area
                    }
                }
            }
            for s in v.subviews { visit(s, depth: depth + 1) }
        }
        var node = superview
        var level = 0
        while let n = node, level < 6 {
            visit(n, depth: 0)
            if best != nil { return best }
            node = n.superview
            level += 1
        }
        return best
    }
}
