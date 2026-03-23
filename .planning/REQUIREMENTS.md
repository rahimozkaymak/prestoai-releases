# Presto AI v1.2 — Requirements

## Milestone Goal
Ship a polished, stable v1.2 that adds system theme support, dramatically improves the response overlay, and fixes critical gaps.

---

## R1: Overlay Rich Text & Interaction
- **R1.1** Markdown rendering in response overlay (headings, bold, italic, lists, links)
- **R1.2** Code syntax highlighting with language detection
- **R1.3** Different font sizes/weights for headings vs body vs code (typographic hierarchy)
- **R1.4** Copy response text button
- **R1.5** Streaming performance — replace O(n²) innerHTML concatenation with incremental DOM append
- **R1.6** Clickable links in responses (open in default browser)

## R2: Overlay Position & Dragging
- **R2.1** Overlay draggable from top bar to any screen position
- **R2.2** Persist overlay position across sessions (UserDefaults or similar)
- **R2.3** Restore saved position on next overlay appearance
- **R2.4** Sensible default position (center-right of screen) on first launch
- **R2.5** Handle multi-monitor — clamp position to visible screen bounds

## R3: System Light/Dark Mode
- **R3.1** Create centralized `Theme.swift` with adaptive color definitions (light + dark variants)
- **R3.2** Remove all hardcoded `.darkAqua` appearance forcing and `.preferredColorScheme(.dark)`
- **R3.3** Migrate all SwiftUI views to use theme-aware colors: SetupWizardView, SettingsView, PaywallView, AuthViews
- **R3.4** Migrate OverlayManager-3.swift HTML/CSS to theme-aware: white transparent background with black text in light mode, current dark style in dark mode
- **R3.5** Window/panel backgrounds adapt: light semi-transparent in light mode, dark semi-transparent in dark mode
- **R3.6** Consolidate duplicate color palettes (SetupWizardView WZ + PaywallView have separate identical palettes)
- **R3.7** Respond to real-time system appearance changes (no app restart needed)
- **R3.8** Tint colors, shadows, gradients, and opacity levels adapt appropriately

## R4: Account & Security
- **R4.1** Password reset flow (backend endpoint + client UI)
- **R4.2** Session management — logout endpoint with token invalidation
- **R4.3** Email validation improvements (prevent obviously invalid emails)

## R5: Backend Reliability
- **R5.1** Alembic migration setup (replace create_all())
- **R5.2** Polar webhook error handling — proper error codes, idempotency
- **R5.3** Structured logging (replace print statements with proper logger)
- **R5.4** Dead code cleanup — remove unused free_months system or implement it
- **R5.5** N+1 query fix in promo listing endpoint

## R6: Client UX Polish
- **R6.1** Offline/unreachable backend handling — cached state, clear messaging
- **R6.2** Usage warnings when approaching daily query limit
- **R6.3** Retry logic for transient API failures (beyond just token refresh)
- **R6.4** Image compression failure handling (don't silently send huge PNGs)
- **R6.5** Hardcoded pricing → fetch from backend config

## R7: Website & Growth
- **R7.1** Privacy policy and Terms of Service pages
- **R7.2** Analytics integration (uncomment Plausible or add alternative)
- **R7.3** Dynamic download URL (point to latest release, not hardcoded v0.1.0-dev)
- **R7.4** 404 page
