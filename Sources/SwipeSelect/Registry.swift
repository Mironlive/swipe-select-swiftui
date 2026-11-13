import SwiftUI
import UIKit

/// Where the mounted items are. Frames are stored in "content" coordinates:
/// the frame relative to the scroll container plus the scroll offset at the moment
/// of measuring, so they stay valid while the list scrolls.
@MainActor
final class SwipeSelectRegistry {
    struct Entry {
        var index: Int
        var frame: CGRect
        var pending: Bool
    }

    let space = "SwipeSelect.\(UUID().uuidString)"
    private(set) var entries: [UUID: Entry] = [:]
    weak var scrollView: UIScrollView? {
        didSet { resolvePending() }
    }

    func report(token: UUID, index: Int, frame: CGRect) {
        guard frame.width > 0 || frame.height > 0 else { return }
        if let sv = scrollView {
            let o = sv.contentOffset
            entries[token] = Entry(index: index, frame: frame.offsetBy(dx: o.x, dy: o.y), pending: false)
        } else {
            entries[token] = Entry(index: index, frame: frame, pending: true)
        }
    }

    func remove(token: UUID) {
        entries[token] = nil
    }

    private func resolvePending() {
        guard let o = scrollView?.contentOffset else { return }
        for (k, e) in entries where e.pending {
            entries[k] = Entry(index: e.index, frame: e.frame.offsetBy(dx: o.x, dy: o.y), pending: false)
        }
    }

    /// Item under `point` (content coordinates). Falls back to the nearest one,
    /// so separators, gaps and the space past the last item still resolve.
    func hitTest(_ point: CGPoint, exact: Bool = false) -> Int? {
        var best: Int?
        var bestDistance = CGFloat.infinity
        for e in entries.values where !e.pending {
            let f = e.frame
            if f.contains(point) { return e.index }
            if exact { continue }
            let dx = max(f.minX - point.x, 0, point.x - f.maxX)
            let dy = max(f.minY - point.y, 0, point.y - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestDistance || (d == bestDistance && e.index < (best ?? .max)) {
                bestDistance = d
                best = e.index
            }
        }
        return best
    }
}

private struct RegistryKey: EnvironmentKey {
    static let defaultValue: SwipeSelectRegistry? = nil
}

extension EnvironmentValues {
    var swipeSelectRegistry: SwipeSelectRegistry? {
        get { self[RegistryKey.self] }
        set { self[RegistryKey.self] = newValue }
    }
}

private struct ItemGeometry: Equatable {
    var index: Int
    var frame: CGRect
}

struct SwipeSelectItemModifier: ViewModifier {
    let index: Int
    @Environment(\.swipeSelectRegistry) private var registry
    @State private var token = UUID()

    func body(content: Content) -> some View {
        if let registry {
            content.background(
                GeometryReader { g in
                    let geo = ItemGeometry(index: index, frame: g.frame(in: .named(registry.space)))
                    Color.clear
                        .onAppear { registry.report(token: token, index: geo.index, frame: geo.frame) }
                        .onChange(of: geo) { registry.report(token: token, index: $0.index, frame: $0.frame) }
                        .onDisappear { registry.remove(token: token) }
                }
            )
        } else {
            content
        }
    }
}

extension View {
    /// Marks an item of a list wrapped with `.swipeSelect(...)`. Put it on **every** item,
    /// with the item's index in your data.
    public func swipeSelectItem(_ index: Int) -> some View {
        modifier(SwipeSelectItemModifier(index: index))
    }
}
