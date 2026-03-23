# Presto AI v1.2 — Roadmap

## Phase Overview

| Phase | Name | Requirements | Status |
|-------|------|-------------|--------|
| 1 | Overlay Rich Text | R1.1–R1.6 | not_started |
| 2 | Overlay Position Memory | R2.1–R2.5 | not_started |
| 3 | System Light/Dark Mode | R3.1–R3.8 | not_started |
| 4 | Account & Security | R4.1–R4.3 | not_started |
| 5 | Backend Hardening | R5.1–R5.5 | not_started |
| 6 | Client UX Polish | R6.1–R6.5 | not_started |
| 7 | Website & Growth | R7.1–R7.4 | not_started |

---

## Phase 1: Overlay Rich Text
**Goal:** Transform the response overlay from single-font plain text to a rich reading experience with markdown rendering, typographic hierarchy, code highlighting, and smooth streaming.

**Why first:** This is the core product surface — every user sees it on every query. Claude's responses use markdown (headings, bold, code blocks, lists) but currently render as flat text. This is the single biggest quality gap.

**Requirements:** R1.1, R1.2, R1.3, R1.4, R1.5, R1.6

**Success criteria:**
- `# Heading` renders large and bold, `## Heading` medium bold, etc.
- Body text, headings, and code use distinct font sizes/weights for clear visual hierarchy
- `**bold**` renders bold, `*italic*` renders italic, `-` items render as lists
- ``` code blocks have syntax highlighting with language labels
- Copy button copies full response text to clipboard
- Streaming appends incrementally (no O(n²) innerHTML rebuild)
- Links are clickable and open in default browser
- MathJax still works for LaTeX expressions

**Key files:** `OverlayManager-3.swift` (WKWebView HTML/CSS/JS)

**Approach:** Integrate a lightweight JS markdown library (marked.js) with incremental parsing, plus highlight.js for code blocks. Rework the streaming JS to build a DOM buffer instead of innerHTML concatenation.

---

## Phase 2: Overlay Position Memory
**Goal:** Make the overlay draggable to any screen position and remember that position across sessions.

**Why second:** Quick focused change to the overlay while we're already working on it. Users want to place the overlay where it doesn't block their work.

**Requirements:** R2.1, R2.2, R2.3, R2.4, R2.5

**Success criteria:**
- Overlay draggable by clicking and dragging the top header bar
- Last position saved to UserDefaults on dismiss
- Next overlay appearance restores saved position
- First-ever launch defaults to center-right of main screen
- If saved position is off-screen (monitor disconnected), clamps to nearest visible edge
- Multi-monitor: overlay stays on the screen where it was last placed

**Key files:** `OverlayManager-3.swift`

**Approach:** NSPanel already supports dragging — need to wire the header bar as a drag handle, save frame origin to UserDefaults on `orderOut`, restore on `makeKeyAndOrderFront`.

---

## Phase 3: System Light/Dark Mode
**Goal:** Full system theme support — app follows macOS light/dark mode automatically. Every UI element adapts. Overlay becomes white-transparent with black text in light mode.

**Why third:** Major change touching 7 files and 70+ hardcoded color instances. Must be done after overlay changes (Phases 1-2) so we're not fighting merge conflicts. This phase builds on stable overlay code.

**Requirements:** R3.1, R3.2, R3.3, R3.4, R3.5, R3.6, R3.7, R3.8

**Scope of change (from audit):**
- **7 Swift files** with hardcoded colors
- **70+ color instances** to migrate
- **3 forced dark mode declarations** to remove
- **2 duplicate color palettes** to consolidate
- **HTML/CSS in WKWebView** with hardcoded dark colors

**Success criteria:**
- New `Theme.swift` file with all color definitions, light + dark variants
- `@Environment(\.colorScheme)` drives all views — no forced appearances
- SetupWizardView, SettingsView, PaywallView, AuthViews all use Theme colors
- Overlay: light mode = white semi-transparent bg (#FFFFFF @ 0.92) + black/dark text; dark mode = current dark bg
- Real-time switching: toggling System Settings → Appearance instantly updates all UI (no restart)
- Shadows, gradients, tints, borders all adapt
- No duplicate palette definitions

**Key files (all need changes):**
1. New: `Theme.swift` — centralized adaptive color definitions
2. `PrestoAIApp.swift` — remove `.darkAqua` forcing (lines 36, 152), adapt panel backgrounds
3. `OverlayManager-3.swift` — CSS variables driven by colorScheme, container layer color
4. `SetupWizardView.swift` — replace WZ palette with Theme colors
5. `PaywallView.swift` — replace duplicate palette with Theme colors
6. `SettingsView.swift` — remove `.preferredColorScheme(.dark)`, use Theme colors
7. `AuthViews.swift` — replace all `.white`/`.white.opacity()` with Theme colors

**Approach:**
1. Create `Theme.swift` with `static func` color accessors that take `ColorScheme`
2. Remove all 3 appearance-forcing declarations
3. Systematically migrate each view file
4. For the WKWebView overlay: inject CSS custom properties from Swift based on current colorScheme, listen for appearance change notifications to re-inject

---

## Phase 4: Account & Security
**Goal:** Add password reset, proper session management, and logout so users aren't locked out of their accounts.

**Requirements:** R4.1, R4.2, R4.3

**Success criteria:**
- Password reset email sends a time-limited reset link
- Reset link allows setting new password
- Logout endpoint invalidates tokens server-side
- Client clears all auth state on logout
- Invalid emails rejected at registration

**Key files:** `main.py`, `AuthViews.swift`, `AppStateManager.swift`, `APIService.swift`

---

## Phase 5: Backend Hardening
**Goal:** Make the backend production-grade: proper migrations, logging, webhook reliability, and dead code cleanup.

**Requirements:** R5.1, R5.2, R5.3, R5.4, R5.5

**Success criteria:**
- Alembic initialized with baseline migration matching current schema
- Polar webhooks return proper HTTP error codes and handle replays idempotently
- All print() statements replaced with structured logger calls
- free_months_earned/used system either fully implemented or removed
- Promo list endpoint uses joined query (no N+1)

**Key files:** `main.py`, new `alembic/` directory

---

## Phase 6: Client UX Polish
**Goal:** Handle edge cases gracefully — offline mode, rate limits, compression failures, dynamic pricing.

**Requirements:** R6.1, R6.2, R6.3, R6.4, R6.5

**Success criteria:**
- App shows clear "offline" state when backend unreachable (not silent denial)
- Warning shown at 40/50 daily queries
- Transient 5xx errors retried once automatically
- Image compression failure falls back to resized PNG (not original full-size)
- Pricing in paywall fetched from backend `app_config`

**Key files:** `APIService.swift`, `AppStateManager.swift`, `PaywallView.swift`, `OverlayManager-3.swift`

---

## Phase 7: Website & Growth
**Goal:** Complete the website with legal pages, analytics, and proper download management.

**Requirements:** R7.1, R7.2, R7.3, R7.4

**Success criteria:**
- Privacy policy and ToS pages live at `/privacy` and `/terms`
- Plausible or equivalent analytics tracking page views and downloads
- Download buttons point to latest GitHub release dynamically (GitHub API)
- Custom 404 page with navigation back to home

**Key files:** `prestowebsite/` directory
