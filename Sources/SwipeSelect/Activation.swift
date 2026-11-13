import CoreGraphics
import Foundation

/// When an activation is available.
public enum ActivationWhen: Sendable {
    /// Always.
    case always
    /// Only in selection mode (something is selected, or selection mode is forced on).
    case selectionMode
    /// Only outside selection mode. Handy to let a long press enter the mode
    /// and the edge strip take over afterwards.
    case idle
}

/// Which edge of the list the selection strip is on.
public enum EdgeSide: Sendable {
    /// Left edge (right in right-to-left layouts). Top edge for horizontal lists.
    case leading
    /// The other edge.
    case trailing
}

/// How a selection gesture starts. Combine several in an array.
public enum SwipeSelectActivation: Equatable, Sendable {
    /// A strip along the edge of the list (like mail apps). Dragging inside the strip
    /// selects; outside of it the list scrolls as usual. Taps inside the strip still
    /// reach your own buttons.
    case edge(side: EdgeSide = .leading, width: CGFloat = 56, when: ActivationWhen = .selectionMode)

    /// Long press anywhere on an item (like Photos or Gmail). Until the finger is held,
    /// the list scrolls as usual.
    case longPress(duration: TimeInterval = 0.3, when: ActivationWhen = .always)

    /// Swipe across the list (like iOS Photos in select mode): moving along the list
    /// scrolls, moving across it selects.
    case pan(when: ActivationWhen = .selectionMode)

    var when: ActivationWhen {
        switch self {
        case let .edge(_, _, when), let .longPress(_, when), let .pan(when): return when
        }
    }
}

/// Auto-scroll near the edges of the list.
public struct SwipeSelectAutoScroll: Equatable, Sendable {
    public var isEnabled: Bool
    /// Size of the zone near the edge that triggers auto-scroll, points.
    public var edgeSize: CGFloat
    /// Speed at the inner border of the zone, points per second.
    public var minSpeed: CGFloat
    /// Speed at the very edge, points per second.
    public var maxSpeed: CGFloat

    public init(isEnabled: Bool = true, edgeSize: CGFloat = 60, minSpeed: CGFloat = 120, maxSpeed: CGFloat = 900) {
        self.isEnabled = isEnabled
        self.edgeSize = edgeSize
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
    }

    /// No auto-scroll.
    public static let disabled = SwipeSelectAutoScroll(isEnabled: false)
}

/// What the current gesture does.
public enum DragMode: Sendable { case select, deselect }

/// Where a selection change came from.
public enum SelectionChangeReason: Sendable { case gesture, toggle, api }

/// Passed to `onDragStart` / `onItemEnter` / `onDragEnd`.
public struct SwipeSelectEvent<ID: Hashable> {
    /// Item under the finger.
    public let index: Int
    public let id: ID
    public let mode: DragMode
    /// Selection at the moment of the event.
    public let selected: Set<ID>
}
