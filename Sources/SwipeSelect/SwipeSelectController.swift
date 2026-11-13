import Combine
import Foundation

/// Holds the selection. Observe it from your views.
///
/// During a gesture it publishes every change (so rows update live), but
/// ``onChange`` fires only once — when the gesture ends. Use ``onChange`` to sync
/// with your store without dozens of updates per second.
@MainActor
public final class SwipeSelectController<ID: Hashable>: ObservableObject {
    /// Current selection.
    @Published public private(set) var selected: Set<ID>

    /// Force selection mode on / off, or `nil` to derive it from the selection.
    /// Use it when your app has a "Select" button.
    @Published public var selectionMode: Bool?

    /// A finger is dragging a selection right now.
    @Published public private(set) var isDragging = false

    /// On-screen auto-scroll direction: -1 towards the top / leading edge, 0, 1 towards the bottom / trailing edge.
    @Published public private(set) var autoScrollDirection = 0

    /// Called once per gesture (when it ends) and on every `toggle` / `select` /
    /// `deselect` / `setSelection` / `clear`. Not called by ``sync(_:)``.
    public var onChange: ((Set<ID>, SelectionChangeReason) -> Void)?

    public init(selection: Set<ID> = [], selectionMode: Bool? = nil, onChange: ((Set<ID>, SelectionChangeReason) -> Void)? = nil) {
        selected = selection
        self.selectionMode = selectionMode
        self.onChange = onChange
    }

    /// Selection mode: forced by ``selectionMode``, otherwise on while something is selected.
    public var isSelectionMode: Bool { selectionMode ?? !selected.isEmpty }

    public var count: Int { selected.count }

    public func isSelected(_ id: ID) -> Bool { selected.contains(id) }

    public func toggle(_ id: ID) {
        var next = selected
        if next.remove(id) == nil { next.insert(id) }
        commit(next, .toggle)
    }

    public func select<S: Sequence>(_ ids: S) where S.Element == ID { commit(selected.union(ids), .api) }

    public func deselect<S: Sequence>(_ ids: S) where S.Element == ID { commit(selected.subtracting(ids), .api) }

    public func setSelection<S: Sequence>(_ ids: S) where S.Element == ID { commit(Set(ids), .api) }

    public func clear() { commit([], .api) }

    /// Replaces the selection without calling ``onChange`` — for state that came from the outside.
    public func sync<S: Sequence>(_ ids: S) where S.Element == ID {
        let next = Set(ids)
        if next != selected { selected = next }
    }

    private func commit(_ next: Set<ID>, _ reason: SelectionChangeReason) {
        guard next != selected else { return }
        selected = next
        onChange?(next, reason)
    }

    // MARK: - Used by the gesture

    func gestureUpdate(_ next: Set<ID>) { selected = next }

    func gestureBegan() { isDragging = true }

    func gestureEnded(initial: Set<ID>) {
        isDragging = false
        if autoScrollDirection != 0 { autoScrollDirection = 0 }
        if initial != selected { onChange?(selected, .gesture) }
    }

    func setAutoScrollDirection(_ value: Int) {
        if autoScrollDirection != value { autoScrollDirection = value }
    }
}
