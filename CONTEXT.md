# Presto AI — Project Context (March 2026)

## What Is Presto AI

macOS menu bar app that captures screenshots, sends them to Claude API for analysis, and displays AI responses in a floating overlay. No dock icon — menu bar only. Built with Swift/SwiftUI, backend is Python/FastAPI on Railway.

- **Bundle ID:** `ai.presto.PrestoAI`
- **Domain:** `get-prestoai.com`
- **Backend:** `https://prestoai-backend-production.up.railway.app`
- **Payments:** Polar (polar.sh)
- **AI Model:** Claude Haiku 4.5 (`claude-haiku-4-5-20251001`), max 2048 tokens
- **Distribution:** DMG via GitHub Releases (`rahimozkaymak/prestoai-releases`)
- **Source Code:** `rahimozkaymak/prestoai` (private)

---

## Core Features

### 1. Screenshot Analysis (Cmd+Shift+X)
User presses hotkey → interactive region capture → image compressed (1024px max, JPEG 80%) → POST /api/analyze (SSE stream) → response displayed in floating WKWebView overlay with frosted glass styling. ESC dismisses.

### 2. Quick Prompt (Cmd+Shift+Z)
User presses hotkey → interactive region capture (same as Cmd+Shift+X) → instead of auto-analyzing, shows a text prompt input overlay → user types a specific question about the screenshot → screenshot + custom prompt sent to Claude → streamed response displayed. Useful when the user wants to ask something specific rather than get a generic analysis.

### 3. VisionClick — AI-Driven Mouse Control (Cmd+Shift+D)
User presses hotkey → prompt overlay asks "What should I click?" → full screen captured → screenshot + command sent to Claude → Claude returns `CLICK:x,y` pixel coordinates → cursor moves to target → verification loop (screenshot with cursor visible, Claude confirms or adjusts, up to 3 attempts) → CGEvent click executed. Coordinates are scaled from compressed image space back to screen space.

### 4. Study Mode (Cmd+Shift+S) — In Progress
Proactive screen-aware assistant. When toggled on, periodically captures screen, sends to Claude for context analysis, surfaces suggestions in corner notifications. Persistent prompt box stays on screen. Paid-only feature. Privacy-first: screenshots never written to disk, discarded after API response.

### 5. AutoSolve / Automation — In Progress
Automated task execution using VisionClick. AppSkills define known app interactions. AutomationController orchestrates multi-step workflows. AutomationStatusBar shows progress.

---

## Architecture

### Swift Client (`/Volumes/T7/PrestoAI/PrestoAI/`)

| File | Purpose |
|------|---------|
| **PrestoAIApp.swift** | @main entry, AppDelegate, menu bar, hotkey wiring, auth flow |
| **Views/AppStateManager.swift** | Auth state machine, device ID, JWT tokens (Keychain) |
| **Services/APIService.swift** | HTTP calls, SSE streaming, image compression |
| **Services/HotkeyService.swift** | Global hotkey registration (Carbon API) |
| **Services/ScreenCaptureService.swift** | Interactive screenshot capture |
| **Services/StudyModeManager.swift** | Study Mode capture pipeline and session management |
| **Services/AutoSolveManager.swift** | Auto-solve orchestration |
| **Views/OverlayManager-3.swift** | Floating WKWebView overlay: loading, streaming, errors |
| **Views/PaywallView.swift** | Dual-card paywall (subscribe + referral) |
| **Views/SetupWizardView.swift** | First-launch onboarding wizard |
| **Views/SettingsView.swift** | Settings panel, tabbed |
| **Views/StudyModeViews.swift** | Study Mode UI components |
| **Views/CornerStatusBox.swift** | Corner status indicator |
| **Views/Theme.swift** | App theme/colors |
| **Services/AuthViews.swift** | Account creation/login, checkout polling |
| **Services/LaunchAtLoginManager.swift** | Launch at login toggle |
| **Utils/KeychainHelper.swift** | Keychain CRUD (service: `ai.presto.app`) |
| **VisionClick/VisionClickController.swift** | VisionClick main orchestrator |
| **VisionClick/ClickExecutor.swift** | CGEvent click + highlight circle |
| **VisionClick/AppSkills.swift** | Known app interaction definitions |
| **VisionClick/AutomationController.swift** | Multi-step automation orchestrator |
| **VisionClick/AutomationStatusBar.swift** | Automation progress UI |
| **VisionClick/GridOverlay.swift** | Coordinate grid overlay (legacy, kept for reference) |
| **VisionClick/ZoomCrop.swift** | Crop/zoom utilities (legacy, kept for reference) |

### Backend (Python/FastAPI — separate repo)
- **Repo:** `rahimozkaymak/prestoai-backend` → auto-deploys to Railway
- Single-file: `main.py` (~1060 lines)
- PostgreSQL (prod) / SQLite (dev)
- SQLAlchemy ORM, no Alembic (uses `create_all()`)

### Website (Static — separate directory)
- **Location:** `/Volumes/T7/PrestoAI/prestowebsite/`
- Cloudflare Pages at `get-prestoai.com`
- Pages: index.html, join.html (referral landing), success.html (post-checkout)

---

## App States

| State | Condition | Can Analyze |
|-------|-----------|-------------|
| `.anonymous` | No device ID yet | No |
| `.freeActive` | Device has queries remaining (1–5) | Yes |
| `.freeExhausted` | 5 device queries used | No |
| `.referralActive` | Referral reward active (30 days) | Yes |
| `.paid` | Valid JWT + active subscription | Yes (50/day; 200 admin) |

---

## Monetization

- **Free tier:** 5 lifetime queries per device (UUID in Keychain), no account needed
- **Paid:** Monthly subscription via Polar checkout ($5.99/mo early bird, $10.99/mo post-launch)
- **Referral system:** Copy referral link (PRESTO-XXXXXX) → 3 friends complete an analysis → 30 days free for referrer
- **Promo codes:** Admin-generated, grant free days
- **Study Mode:** Paid-only feature, primary upgrade driver

---

## Backend API (Key Endpoints)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/analyze` | Main SSE streaming analysis (JWT or device_id auth) |
| POST | `/api/auth/register` | Register, returns JWT pair |
| POST | `/api/auth/login` | Login, returns JWT pair |
| GET | `/api/auth/status` | Subscription state check |
| GET | `/api/device/status` | Free queries remaining |
| GET | `/api/billing/checkout-url` | Polar checkout URL |
| POST | `/api/webhooks/polar` | Polar webhook handler |
| GET | `/api/referral/paywall` | Paywall state for device |
| POST | `/api/referral/code` | Create referral code |
| POST | `/api/referral/claim` | Claim referral code |
| GET | `/api/admin/stats` | Admin dashboard |
| POST | `/api/admin/set-premium` | Grant premium manually |
| POST | `/api/v1/study/analyze` | Study Mode analysis (planned) |

---

## Security

- App Sandbox disabled (required for VisionClick accessibility/CGEvent)
- JWT HS256 auth, bcrypt passwords
- Polar webhook signature verification
- Device abuse protection: max 10 device IDs per IP/day
- Screenshots never persisted to disk or server
- Release builds use hardcoded backend URL

---

## UI Pattern

All popups use **OverlayPanel + WKWebView** with frosted glass styling (NSVisualEffectView). Never use plain SwiftUI NSPanel. Dark theme (#0A0A0A). WKWebView ignores CSS drag regions — use local+global NSEvent monitors for window dragging instead.

---

## Deploy Commands

- **Backend:** Push to `rahimozkaymak/prestoai-backend` main → Railway auto-deploys
- **Website:** `CLOUDFLARE_API_TOKEN=<token> wrangler pages deploy /Volumes/T7/PrestoAI/prestowebsite --project-name=prestoai-website`
- **DMG Release:** Build archive in Xcode → export → create DMG → upload to `rahimozkaymak/prestoai-releases` GitHub Releases
- **Source code:** Push to `rahimozkaymak/prestoai` (private)

---

## Known TODOs

- Replace `create_all()` with Alembic migrations
- Device IDs are client-generated (spoofable)
- In-memory IP tracker resets on deploy (consider Redis)
- Web referral landing page not yet built
- Study Mode implementation in progress
- AutoSolve/Automation system in progress
