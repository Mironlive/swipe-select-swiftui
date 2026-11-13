import XCTest
@testable import SwipeSelect

private let keys = (0..<20).map { "k\($0)" }
private func key(_ i: Int) -> String? { i >= 0 && i < keys.count ? keys[i] : nil }

/// Simulates a gesture: starts at `anchor`, then the finger passes `path`.
private func drag(_ initial: [String], _ anchor: Int, _ path: [Int], selectable: ((Int) -> Bool)? = nil) -> [String] {
    let start = Set(initial)
    let shouldSelect = !start.contains(keys[anchor])
    var current = start
    var previous: IndexRange?
    for i in [anchor] + path {
        let next = IndexRange(anchor, i)
        if let changed = applyRangeTransition(initial: start, current: current, previous: previous, next: next,
                                              shouldSelect: shouldSelect, id: key, isSelectable: selectable) {
            current = changed
        }
        previous = next
    }
    return current.sorted { Int($0.dropFirst())! < Int($1.dropFirst())! }
}

final class RangeTests: XCTestCase {
    func testDown() { XCTAssertEqual(drag([], 2, [3, 4, 5]), ["k2", "k3", "k4", "k5"]) }
    func testUp() { XCTAssertEqual(drag([], 5, [4, 3]), ["k3", "k4", "k5"]) }
    func testMovingBackRestores() {
        XCTAssertEqual(drag(["k4"], 1, [2, 3, 4, 5, 6, 3]), ["k1", "k2", "k3", "k4"])
        XCTAssertEqual(drag(["k4"], 1, [6, 1]), ["k1", "k4"])
    }
    func testCrossingAnchor() { XCTAssertEqual(drag([], 5, [7, 3]), ["k3", "k4", "k5"]) }
    func testStartingOnSelectedDeselects() { XCTAssertEqual(drag(["k1", "k2", "k3", "k9"], 2, [3, 4]), ["k1", "k9"]) }
    func testDeselectAndBack() { XCTAssertEqual(drag(["k1", "k2", "k3", "k4"], 1, [4, 2]), ["k3", "k4"]) }
    func testJump() { XCTAssertEqual(drag([], 0, [10]).count, 11) }
    func testNotSelectable() { XCTAssertEqual(drag([], 0, [5], selectable: { $0 != 3 }), ["k0", "k1", "k2", "k4", "k5"]) }
    func testOutsideUntouched() { XCTAssertEqual(drag(["k15", "k16"], 2, [4]), ["k2", "k3", "k4", "k15", "k16"]) }
    func testNoChangeReturnsNil() {
        XCTAssertNil(applyRangeTransition(initial: ["k1"], current: ["k1"], previous: nil, next: IndexRange(1, 1),
                                          shouldSelect: true, id: key))
    }
    func testBigJumpBackAndForth() {
        XCTAssertEqual(drag([], 10, [0, 19, 10]), ["k10"])
    }
}
