# Phase 2: Overlay Position Memory — Execution Plan

**Goal:** Make the overlay draggable to any screen position and remember that position across sessions.

**Key file:** `PrestoAI/Views/OverlayManager-3.swift`

**Status:** 5 of 5 requirements already implemented. Only improvement: replace off-screen reset-to-default with clamping to nearest visible edge.

---

## Pre-existing Implementation

The following are **already working** and require no changes:

- **R2.1** Draggable from top bar — CSS `-webkit-app-region: drag` on `.drag-bar`, `isMovableByWindowBackground = false`
- **R2.2** Persist position — `savedFrame` property saves to UserDefaults (`overlayWindowFrame` key) on dismiss and resize end
- **R2.3** Restore saved position — `ensureWindow()` checks `savedFrame` and uses it if available
- **R2.4** Default position — `defaultFrame()` returns top-right of main screen with 20px padding

---

## Tasks

### Task 1: Improve off-screen handling — clamp to nearest visible edge instead of resetting

**What:** Replace the binary `screenContains()` check (either fully on-screen → use, or not → reset to default) with a clamping function that moves the saved frame to the nearest visible screen edge, preserving the user's size and relative position.

**Files:** `OverlayManager-3.swift`

**Current behavior (line 217):**
```swift
if let saved = savedFrame, screenContains(saved) {
    frame = saved
} else {
    frame = defaultFrame()
}
```

**New behavior:** Replace `screenContains()` with `clampToScreen()` that:
1. Finds the closest screen to the saved frame's center
2. Adjusts origin so the frame fits within that screen's `visibleFrame`
3. Preserves the saved size (width/height)

**Changes:**

Replace `screenContains` and update `ensureWindow`:

```swift
private func clampToScreen(_ rect: NSRect) -> NSRect? {
    // Find the screen closest to the saved frame's center
    let center = NSPoint(x: rect.midX, y: rect.midY)
    guard let screen = NSScreen.screens.min(by: { screenA, screenB in
        let dA = hypot(screenA.visibleFrame.midX - center.x, screenA.visibleFrame.midY - center.y)
        let dB = hypot(screenB.visibleFrame.midX - center.x, screenB.visibleFrame.midY - center.y)
        return dA < dB
    }) else { return nil }

    let sf = screen.visibleFrame
    var clamped = rect
    // Clamp position to keep frame within visible area
    clamped.origin.x = min(max(clamped.origin.x, sf.minX), sf.maxX - clamped.width)
    clamped.origin.y = min(max(clamped.origin.y, sf.minY), sf.maxY - clamped.height)
    return clamped
}
```

Update `ensureWindow()`:
```swift
if let saved = savedFrame, let clamped = clampToScreen(saved) {
    frame = clamped
} else {
    frame = defaultFrame()
}
```

Remove the old `screenContains` method (no longer needed).

**Verify:** Drag overlay to right edge of screen. Dismiss. Disconnect external monitor (or resize screen). Relaunch — overlay should appear clamped to the nearest edge of the remaining screen, not reset to default top-right.

---

## Testing Checklist

- [ ] Drag overlay by top bar to a new position — works
- [ ] Dismiss overlay (ESC) — position saved
- [ ] Trigger new analysis — overlay appears at saved position
- [ ] Resize overlay, dismiss, retrigger — size and position both restored
- [ ] First launch (no saved frame) — overlay appears top-right with 20px padding
- [ ] Move overlay partially off-screen, dismiss, retrigger — clamped to visible area
- [ ] Multi-monitor: drag to second screen, dismiss, retrigger — appears on second screen
