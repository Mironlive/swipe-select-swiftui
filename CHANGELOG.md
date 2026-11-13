# Changelog

## 0.1.0

First public release.

- `.swipeSelect(...)` for `ScrollView` (`LazyVStack`, `LazyVGrid`, `LazyHStack`, …) and `List`, `.swipeSelectItem(index)` for items
- `SwipeSelectController` — selection, selection mode, `onChange` once per gesture, `sync` for outside state
- Activation: edge strip (leading / trailing), long press, swipe across; combine several with `ActivationWhen` (`always` / `selectionMode` / `idle`)
- Auto-scroll that ramps up towards the edge
- Moving back restores what was selected before the gesture
- Vertical and horizontal lists, grids, items of any size, right-to-left layouts
- Non-selectable items, drag callbacks for haptics
