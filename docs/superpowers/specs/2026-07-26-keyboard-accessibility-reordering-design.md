# Design Spec: Keyboard-Accessible Drag-Reordering in Settings (#3)

## Overview
Add accessibility actions (`.accessibilityAction`) to row items in the Menu Bar and Panels tabs of `SettingsView.swift` so VoiceOver users can reorder items using the keyboard without needing mouse drag-and-drop.

## Proposed Changes

### `Sources/PerformanceApp/SettingsView.swift`

1. **`MenuBarTab` / Menu Bar Icons List**:
   Add custom accessibility actions `Move Up` and `Move Down` on each metric row:
   - `Move Up`: moves item to `index - 1` when `index > 0`.
   - `Move Down`: moves item to `index + 1` when `index < count - 1`.

2. **`PanelsTab` / `PanelMiniCard`**:
   Add custom accessibility actions `Move Earlier` and `Move Later` on each panel card:
   - `Move Earlier`: swaps item with `index - 1` when `index > 0`.
   - `Move Later`: swaps item with `index + 1` when `index < count - 1`.

## Verification
- Code review ensuring state mutations occur inside `withAnimation` and bounds checks are enforced.
- Verify accessibility action labels are clear and localized.
