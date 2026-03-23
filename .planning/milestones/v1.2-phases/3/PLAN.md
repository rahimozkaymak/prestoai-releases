# Phase 3: System Light/Dark Mode — Execution Plan

**Goal:** Full system theme support — app follows macOS light/dark mode automatically. Every UI element adapts. Overlay becomes white-transparent with black text in light mode.

**Scope:** 7 files, 70+ hardcoded color instances, 3 forced dark mode declarations, 2 duplicate palettes.

---

## Architecture

**Approach:** Create a centralized `Theme.swift` that provides adaptive colors based on `ColorScheme`. All views read from Theme instead of hardcoded values. The overlay's HTML/CSS uses CSS custom properties injected from Swift based on current appearance.

**Color mapping strategy:**
- Dark mode colors stay exactly as they are today (no visual change for dark mode users)
- Light mode gets inverted equivalents: dark backgrounds → light backgrounds, white text → dark text
- Accent colors (blue buttons, red errors, green success) use SwiftUI system colors which adapt automatically

---

## Tasks

### Task 1: Create Theme.swift — centralized adaptive color system

**What:** Create a new file `PrestoAI/Views/Theme.swift` with all color definitions for both light and dark mode. This consolidates the duplicate WZ palette (SetupWizardView) and PaywallView palette into one source.

**File:** New `PrestoAI/Views/Theme.swift`

**Design:**
```swift
import SwiftUI

enum Theme {
    // MARK: - Backgrounds
    static func bg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.039, green: 0.039, blue: 0.039) // #0A0A0A
                        : Color(red: 0.98, green: 0.98, blue: 0.98)   // #FAFAFA
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.110, green: 0.110, blue: 0.110) // #1C1C1C
                        : Color(red: 0.95, green: 0.95, blue: 0.95)   // #F2F2F2
    }
    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.165, green: 0.165, blue: 0.165) // #2A2A2A
                        : Color(red: 0.85, green: 0.85, blue: 0.85)   // #D9D9D9
    }

    // MARK: - Text
    static func text1(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.878, green: 0.878, blue: 0.878) // #E0E0E0
                        : Color(red: 0.10, green: 0.10, blue: 0.10)   // #1A1A1A
    }
    static func text2(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.467, green: 0.467, blue: 0.467) // #777
                        : Color(red: 0.45, green: 0.45, blue: 0.45)   // #737373
    }
    static func text3(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.333, green: 0.333, blue: 0.333) // #555
                        : Color(red: 0.60, green: 0.60, blue: 0.60)   // #999
    }
    static func text4(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.400, green: 0.400, blue: 0.400) // #666
                        : Color(red: 0.55, green: 0.55, blue: 0.55)   // #8C8C8C
    }
    static func textDot(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.533, green: 0.533, blue: 0.533) // #888
                        : Color(red: 0.50, green: 0.50, blue: 0.50)   // #808080
    }

    // MARK: - Keys (setup wizard)
    static func keyBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.133, green: 0.133, blue: 0.133) // #222
                        : Color(red: 0.92, green: 0.92, blue: 0.92)   // #EBEBEB
    }
    static func keyBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.200, green: 0.200, blue: 0.200) // #333
                        : Color(red: 0.80, green: 0.80, blue: 0.80)   // #CCCCCC
    }
    static func keyActive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.180, green: 0.180, blue: 0.180) // #2E2E2E
                        : Color(red: 0.88, green: 0.88, blue: 0.88)   // #E0E0E0
    }
    static func keyFlash(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.220, green: 0.220, blue: 0.220) // #383838
                        : Color(red: 0.85, green: 0.85, blue: 0.85)   // #D9D9D9
    }

    // MARK: - Subtle overlays (buttons, inputs, dividers)
    static func subtleBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }
    static func subtleBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    static func inputBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    // MARK: - NSColor versions for AppKit panels
    static func nsBg(_ appearance: NSAppearance?) -> NSColor {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1.0)
                      : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
    }
    static func nsOverlayBg(_ appearance: NSAppearance?) -> NSColor {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0.07, green: 0.07, blue: 0.078, alpha: 0.92)
                      : NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.92)
    }
}
```

**Verify:** File compiles. Both `Theme.bg(.dark)` and `Theme.bg(.light)` return distinct colors.

---

### Task 2: Migrate PrestoAIApp.swift — remove forced appearances, use Theme

**What:** Remove `.darkAqua` forcing, use `Theme.nsBg()` for panel backgrounds that respond to system appearance.

**File:** `PrestoAIApp.swift`

**Changes:**
- **Line 32**: Replace hardcoded `NSColor(red: 0.039...)` with `Theme.nsBg(panel.effectiveAppearance)` — but since panel isn't shown yet, use `NSApp.effectiveAppearance`
- **Line 36**: **Remove** `panel.appearance = NSAppearance(named: .darkAqua)` entirely
- **Line 150**: Replace hardcoded `NSColor(red: 0.039...)` with `Theme.nsBg(NSApp.effectiveAppearance)`
- **Line 152**: **Remove** `window.appearance = NSAppearance(named: .darkAqua)` entirely

**Verify:** Launch app in light mode — panels have light background. Toggle to dark mode in System Settings — panels switch to dark background without restart.

---

### Task 3: Migrate SetupWizardView.swift — replace WZ palette with Theme

**What:** Remove the local `WZ` enum. Replace all `WZ.xxx` references with `Theme.xxx(colorScheme)`. Add `@Environment(\.colorScheme) var colorScheme` to each view struct.

**File:** `SetupWizardView.swift`

**Changes:**
- **Lines 15-28**: Delete entire `WZ` enum
- Add `@Environment(\.colorScheme) var colorScheme` to SetupWizardView and any sub-view structs
- Replace all usages:
  - `WZ.bg` → `Theme.bg(colorScheme)`
  - `WZ.surface` → `Theme.surface(colorScheme)`
  - `WZ.border` → `Theme.border(colorScheme)`
  - `WZ.text1` → `Theme.text1(colorScheme)`
  - `WZ.text2` → `Theme.text2(colorScheme)`
  - `WZ.text3` → `Theme.text3(colorScheme)`
  - `WZ.text4` → `Theme.text4(colorScheme)`
  - `WZ.textDot` → `Theme.textDot(colorScheme)`
  - `WZ.keyBg` → `Theme.keyBg(colorScheme)`
  - `WZ.keyBorder` → `Theme.keyBorder(colorScheme)`
  - `WZ.keyActive` → `Theme.keyActive(colorScheme)`
  - `WZ.keyFlash` → `Theme.keyFlash(colorScheme)`
- Replace `.foregroundColor(.white)` → `.foregroundColor(Theme.text1(colorScheme))`
- Replace `Color.white.opacity(0.08)` / `Color.white.opacity(0.10)` → `Theme.subtleBorder(colorScheme)` / `Theme.inputBg(colorScheme)`
- Replace `Color(white: 0.867)` and `Color(white: 0.6)` key text → Theme equivalents

**Verify:** Setup wizard renders correctly in both light and dark mode. Key animations still work. Referral code input visible in both modes.

---

### Task 4: Migrate PaywallView.swift — replace duplicate palette with Theme

**What:** Remove the local color variables (bg, surface, border, text1, text2). Replace with Theme calls.

**File:** `PaywallView.swift`

**Changes:**
- **Lines 27-31**: Delete local `bg`, `surface`, `border`, `text1`, `text2` variables
- Add `@Environment(\.colorScheme) var colorScheme`
- Replace all `bg` → `Theme.bg(colorScheme)`, `surface` → `Theme.surface(colorScheme)`, etc.
- Replace `.foregroundColor(.white)` → `.foregroundColor(Theme.text1(colorScheme))`
- Replace `Color.white.opacity(0.10)` → `Theme.inputBg(colorScheme)`
- Keep `.foregroundColor(.green)` and `Color.blue` as-is (system colors adapt automatically)

**Verify:** Paywall shows correctly in both modes. Subscribe button still blue. Referral progress indicators visible.

---

### Task 5: Migrate SettingsView.swift — remove preferredColorScheme, use Theme

**What:** Remove `.preferredColorScheme(.dark)`, replace all hardcoded colors.

**File:** `SettingsView.swift`

**Changes:**
- **Line 49**: **Remove** `.preferredColorScheme(.dark)`
- **Line 48**: Replace `Color(red: 0.039...)` → `Theme.bg(colorScheme)`
- Add `@Environment(\.colorScheme) var colorScheme`
- Replace `.foregroundColor(.white)` → `.foregroundColor(Theme.text1(colorScheme))`
- Replace `.foregroundColor(.white.opacity(0.7))` → `.foregroundColor(Theme.text2(colorScheme))`
- Replace `.foregroundColor(.white.opacity(0.5))` → `.foregroundColor(Theme.text3(colorScheme))`
- Replace `.foregroundColor(.white.opacity(0.35))` → `.foregroundColor(Theme.text4(colorScheme))`
- Replace `Color.white.opacity(0.07)` → `Theme.subtleBg(colorScheme)`
- Replace `Color.white.opacity(0.08)` → `Theme.subtleBorder(colorScheme)`
- Replace `Color(white: 0.55)` tint → `Theme.text3(colorScheme)`
- Keep `.colorMultiply(Color(red: 1.0, green: 0.78, blue: 0.08))` (gold badge stays gold in both modes)

**Verify:** Settings panel renders in both modes. Toggle switch, text editor, tabs all adapt.

---

### Task 6: Migrate AuthViews.swift — use Theme colors

**What:** Replace all hardcoded colors in auth views.

**File:** `AuthViews.swift`

**Changes:**
- Add `@Environment(\.colorScheme) var colorScheme` to each view struct
- **Lines 72, 194, 300**: Replace `Color(red: 0.039...)` → `Theme.bg(colorScheme)`
- Replace `.foregroundColor(.white)` → `.foregroundColor(Theme.text1(colorScheme))`
- Replace `.foregroundColor(.white.opacity(0.7))` → `.foregroundColor(Theme.text2(colorScheme))`
- Replace `.foregroundColor(.white.opacity(0.5))` → `.foregroundColor(Theme.text3(colorScheme))`
- Replace `Color.white.opacity(0.1)` → `Theme.inputBg(colorScheme)`
- Replace `Color.white.opacity(0.08)` → `Theme.subtleBorder(colorScheme)`
- Keep `Color.blue`, `.red` as-is (system colors)

**Verify:** Login, register, checkout views all render in both modes. Error text visible. Buttons visible.

---

### Task 7: Migrate OverlayManager-3.swift — theme-aware CSS + container background

**What:** Make the overlay's HTML/CSS and container layer adapt to system appearance. In light mode: white semi-transparent background, dark text. In dark mode: current dark style.

**File:** `OverlayManager-3.swift`

**Changes:**

**7a. Container layer background (line 305):**
Replace hardcoded NSColor with Theme:
```swift
container.layer?.backgroundColor = Theme.nsOverlayBg(NSApp.effectiveAppearance).cgColor
```

**7b. Observe appearance changes to update container + reload CSS:**
Add appearance observation. When system theme changes while overlay is visible, update container background color and inject new CSS variables.

Add a method:
```swift
private func updateTheme() {
    guard let container = overlayWindow?.contentView else { return }
    container.layer?.backgroundColor = Theme.nsOverlayBg(NSApp.effectiveAppearance).cgColor
    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    webView?.evaluateJavaScript("if(typeof setTheme==='function')setTheme(\(isDark))", completionHandler: nil)
}
```

Register for appearance change notifications in `createWindow`:
```swift
DistributedNotificationCenter.default().addObserver(
    self, selector: #selector(systemThemeChanged),
    name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil
)
```

**7c. CSS variables in sharedHead:**
Add CSS custom properties at the top of the `<style>` block, with a JS `setTheme(isDark)` function that swaps them:

```css
:root {
    --bg: rgba(18,18,20,0.60);
    --text: #f0f0f2;
    --text-dim: rgba(255,255,255,0.28);
    --subtle-bg: rgba(255,255,255,0.08);
    --subtle-border: rgba(255,255,255,0.15);
    --code-bg: rgba(0,0,0,0.3);
    --code-inline-bg: rgba(255,255,255,0.08);
    --blockquote-border: rgba(255,255,255,0.2);
    --blockquote-text: rgba(240,240,242,0.7);
    --link-color: #6cb4ff;
    --table-header-bg: rgba(255,255,255,0.06);
    --spinner-border: rgba(255,255,255,0.1);
    --spinner-accent: rgba(255,255,255,0.5);
    --loading-text: rgba(255,255,255,0.4);
    --error-color: #ff6b6b;
    --logo-filter: invert(1);
    --copy-color: #f0f0f2;
}
```

Light mode equivalents:
```css
:root.light {
    --bg: rgba(255,255,255,0.60);
    --text: #1a1a1a;
    --text-dim: rgba(0,0,0,0.25);
    --subtle-bg: rgba(0,0,0,0.05);
    --subtle-border: rgba(0,0,0,0.10);
    --code-bg: rgba(0,0,0,0.05);
    --code-inline-bg: rgba(0,0,0,0.06);
    --blockquote-border: rgba(0,0,0,0.15);
    --blockquote-text: rgba(0,0,0,0.6);
    --link-color: #0066cc;
    --table-header-bg: rgba(0,0,0,0.04);
    --spinner-border: rgba(0,0,0,0.1);
    --spinner-accent: rgba(0,0,0,0.4);
    --loading-text: rgba(0,0,0,0.4);
    --error-color: #cc0000;
    --logo-filter: invert(0);
    --copy-color: #1a1a1a;
}
```

Replace all hardcoded CSS values with `var(--xxx)`:
- `background: rgba(18,18,20,0.60)` → `background: var(--bg)`
- `color: #f0f0f2` → `color: var(--text)`
- All other colors → corresponding CSS variables

**JS setTheme function:**
```javascript
function setTheme(isDark) {
    document.documentElement.className = isDark ? '' : 'light';
}
```

**7d. Pass initial theme when loading HTML:**
In `sharedHead`, add inline script that checks initial state. Also pass theme from Swift when loading:

In `responseHTML`, `loadingHTML`, `errorHTML` — determine current theme and pass it:
```swift
let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
// Add to HTML: <script>setTheme(\(isDark))</script> at end of <body>
```

**7e. highlight.js theme:**
The current `github-dark.min.css` only works for dark mode. For light mode, use `github.min.css`. Load both and toggle with CSS:
```css
/* In dark mode, github-dark is active (default) */
/* In light mode (.light class), hide dark theme */
```
Or simpler: load both stylesheets, disable one based on theme class.

**Verify:** Toggle system appearance. Overlay updates in real-time: dark mode = current dark style, light mode = white semi-transparent bg with dark text. Code highlighting theme matches. Loading spinner, error text, ESC hint all visible in both modes.

---

## Execution Order

1. **Task 1** — Create Theme.swift (no dependencies, foundation for everything)
2. **Tasks 2-6** — Migrate all SwiftUI views + PrestoAIApp (all depend on Task 1, independent of each other)
3. **Task 7** — Migrate OverlayManager (depends on Task 1 for NSColor helpers)

---

## Testing Checklist

- [ ] App launches in light mode — all panels have light backgrounds
- [ ] App launches in dark mode — everything looks identical to current
- [ ] Toggle system appearance — all UI updates in real-time (no restart)
- [ ] Setup wizard: all 3 steps render correctly in both modes
- [ ] Setup wizard: keyboard key animation works in both modes
- [ ] Settings panel: tabs, toggle, text editor visible in both modes
- [ ] Paywall: subscribe and referral cards visible in both modes
- [ ] Auth views: login/register/checkout forms visible in both modes
- [ ] Overlay response: light mode = white-transparent bg, dark text
- [ ] Overlay response: dark mode = current dark style unchanged
- [ ] Overlay: code highlighting theme matches mode (github-dark vs github)
- [ ] Overlay: copy button, ESC hint, drag bar all visible in both modes
- [ ] Overlay: loading spinner visible in both modes
- [ ] Overlay: error text visible in both modes
- [ ] Overlay: links visible and clickable in both modes
- [ ] Gold pro badge stays gold in both modes
- [ ] Blue buttons remain blue in both modes
- [ ] Red error text remains visible in both modes
- [ ] Green success indicators remain visible in both modes
