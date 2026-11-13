/// Inclusive range of item indices.
public struct IndexRange: Equatable, Sendable {
    public let lower: Int
    public let upper: Int

    public init(_ a: Int, _ b: Int) {
        lower = min(a, b)
        upper = max(a, b)
    }

    public func contains(_ i: Int) -> Bool { i >= lower && i <= upper }
}

/// Moves the selection from `previous` range to `next` range.
///
/// Items entering the range get the gesture mode, items leaving it get back their
/// state from `initial`. Only the difference between the ranges is touched, so the
/// cost doesn't depend on how long the range is. Both ranges must contain the anchor.
///
/// - Returns: the new selection, or `nil` when nothing changed.
public func applyRangeTransition<ID: Hashable>(
    initial: Set<ID>,
    current: Set<ID>,
    previous: IndexRange?,
    next: IndexRange,
    shouldSelect: Bool,
    id: (Int) -> ID?,
    isSelectable: ((Int) -> Bool)? = nil
) -> Set<ID>? {
    var result: Set<ID>?

    func set(_ i: Int, inRange: Bool) {
        guard let key = id(i) else { return }
        if isSelectable?(i) == false { return }
        let want = inRange ? shouldSelect : initial.contains(key)
        let has = (result ?? current).contains(key)
        if want == has { return }
        if result == nil { result = current }
        if want { result!.insert(key) } else { result!.remove(key) }
    }

    func visit(_ lo: Int, _ hi: Int) {
        guard lo <= hi else { return }
        for i in lo...hi { set(i, inRange: next.contains(i)) }
    }

    if let p = previous {
        visit(min(p.lower, next.lower), max(p.lower, next.lower) - 1)
        visit(min(p.upper, next.upper) + 1, max(p.upper, next.upper))
        // Ranges that don't overlap (shouldn't happen, both contain the anchor).
        if p.upper < next.lower || next.upper < p.lower {
            visit(p.lower, p.upper)
            visit(next.lower, next.upper)
        }
    } else {
        visit(next.lower, next.upper)
    }
    return result
}
