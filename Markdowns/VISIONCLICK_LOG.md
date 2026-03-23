# VisionClick Development Log — 2026-03-20

## What We Built

Replaced the Accessibility Tree Scanner (Cmd+Shift+D) with a **Vision-Based Grid Click System** that lets users click any on-screen element by describing it in natural language.

## Final Architecture

1. User presses **Cmd+Shift+D** → prompt overlay appears ("What should I click?")
2. User types command (e.g. "click Wikipedia") → overlay dismisses
3. Full screen captured via `screencapture -x`
4. Screenshot sent to Claude API with compressed image dimensions → Claude returns `CLICK:x,y` pixel coordinates
5. Coordinates scaled from compressed image space (1024px max) back to screen space (~1.4x on retina)
6. **Verification loop**: cursor moves to target (no click), screenshot taken with cursor visible (`-C` flag), Claude confirms (`CONFIRM`) or provides adjustment (`ADJUST:dx,dy`) — up to 3 attempts
7. Click executed via CGEvent

## Files

### Created
- `PrestoAI/VisionClick/GridOverlay.swift` — coordinate grid overlay (kept for potential future use)
- `PrestoAI/VisionClick/ZoomCrop.swift` — crop/zoom utilities (kept for potential future use)
- `PrestoAI/VisionClick/ClickExecutor.swift` — CGEvent click + red highlight circle + typeText foundation
- `PrestoAI/VisionClick/VisionClickController.swift` — main orchestrator

### Deleted
- `PrestoAI/Accessibility/` — entire folder (AccessibilityScanner, AccessibilityExecutor, AccessibilityOverlay, ScannedElement)

### Modified
- `HotkeyService.swift` — Cmd+Shift+D hotkey (ID 5) with `onAccessibilityScan` callback
- `PrestoAIApp.swift` — `performVisionClick()` replaces `performAccessibilityScan()`, captures target app before overlay
- `OverlayManager-3.swift` — removed accessibility scan HTML, added `placeholder` param to `showPromptInput()`
- `APIService.swift` — default API URL to production Railway for all builds (sandbox change broke UserDefaults container)
- `PrestoAI.entitlements` — sandbox disabled (`app-sandbox = false`), removed `automation.apple-events`
- `Info.plist` — removed `NSAccessibilityUsageDescription`
- `project.pbxproj` — `ENABLE_APP_SANDBOX = NO`

## Bugs Fixed (chronological)

### 1. Accessibility scanner returned 0 elements
**Cause**: `showLoading()` called `NSApp.activate()` which made Presto AI the frontmost app before the scanner ran — it was scanning itself.
**Fix**: Capture `NSRunningApplication` reference before showing overlay.

### 2. Accessibility scanner still returned 0 elements
**Cause**: App Sandbox blocks AX API inter-process communication.
**Fix**: Disabled App Sandbox (`ENABLE_APP_SANDBOX = NO`). Required for DMG-distributed apps using accessibility.

### 3. "Unable to connect to Presto AI servers"
**Cause**: Disabling sandbox moved the UserDefaults container. The `apiBaseURL` override pointing to Railway production was in the old sandboxed container. Debug builds fell back to `localhost:8000`.
**Fix**: Changed default API URL from localhost to production Railway for all builds.

### 4. "Could not capture the frontmost window"
**Cause**: Same race condition — frontmost app captured after overlay activation. Also `CGWindowListCopyWindowInfo` needs Screen Recording permission (reset by sandbox change).
**Fix**: Capture target app before overlay, added screen recording permission check.

### 5. Still couldn't capture window
**Cause**: Screen Recording permission was reset when sandbox settings changed.
**Fix**: User re-granted permission in System Settings.

### 6. Claude returned verbose explanations instead of `CELL:G4`
**Cause**: Backend's `/api/analyze` endpoint adds its own system prompt for screenshot explanation, overriding our terse format instructions.
**Fix**: Made prompts much more forceful with "Your ENTIRE response must be exactly..." phrasing.

### 7. Clicked wrong location (coordinates halved)
**Cause**: Code divided coordinates by `backingScaleFactor` (2x on retina), but NSImage coordinates from `screencapture` are already in screen points.
**Fix**: Removed the retina scaling division.

### 8. Clicked wrong location (coordinates ~30% off)
**Cause**: `ImageCompressor.compress()` resizes screenshots to 1024px max side before sending to Claude. Claude returned coordinates for the compressed ~1024x640 image, but we used them as 1440x900 screen coordinates.
**Fix**: Compute compression scale factor, tell Claude the compressed dimensions, and scale returned coordinates back to screen space.

### 9. Switched from per-window to full-screen capture
User wanted to click anything on screen, not just elements in a single window.

### 10. Added cursor verification loop
User's idea: move cursor first (no click), take screenshot with cursor visible, ask Claude to confirm or adjust. Up to 3 attempts for self-calibration.

### 11. Replaced grid system with direct pixel coordinates
Grid+zoom+fine-grid pipeline accumulated coordinate errors. Simplified to: one API call for direct `CLICK:x,y` coordinates + verification loop.
