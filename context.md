# Presto AI — Project Context

## Overview
macOS menu bar app: capture a screenshot region → AI analysis → floating overlay response. No dock icon, menu bar only.

**Hotkeys:** `Cmd+Shift+X` (capture), `ESC` (dismiss overlay)
**Domain:** `get-prestoai.com`
**Backend:** Railway (`https://prestoai-backend-production.up.railway.app`)
**Payments:** Polar (polar.sh) — NOT LemonSqueezy

---

## Architecture

### Client (macOS App — Swift/SwiftUI)
- **Location:** `/Volumes/T7/PrestoAI/PrestoAI/`
- Xcode project: `PrestoAI.xcodeproj`
- Menu bar app (`.accessory` activation policy), dark theme (`#0A0A0A`)

### Backend (Python/FastAPI)
- **Location:** `/Volumes/T7/PrestoAI/Presto backend/main.py`
- Single-file FastAPI app, SQLAlchemy ORM, v1.2.0
- AI model: `claude-haiku-4-5-20251001`, max 2048 tokens
- Production: PostgreSQL (Railway), Dev: SQLite

### Website (Static)
- **Location:** `/Volumes/T7/PrestoAI/prestowebsite/`
- Hosted on Cloudflare Pages at `get-prestoai.com`
- Pages: `index.html`, `join.html` (referral landing), `success.html` (post-checkout)
- **Deploy:** `CLOUDFLARE_API_TOKEN=hFwCOMNPr4k2oHQ5Hh0ds9lUi8YZeIWT_cZCGoUL wrangler pages deploy /Volumes/T7/PrestoAI/prestowebsite --project-name=prestoai-website`
- **DMG Release:** GitHub Releases on `rahimozkaymak/prestoai-releases` — download buttons link to latest release

---

## Key Files

### Swift Client
| File | Purpose |
|------|---------|
| `PrestoAIApp.swift` | `@main` entry, AppDelegate, menu bar, hotkey wiring, auth flow |
| `Views/AppStateManager.swift` | Single source of truth: auth state, device ID, JWT tokens (Keychain) |
| `Services/APIService.swift` | HTTP calls, SSE streaming, image compression (1024px max, JPEG 80%) |
| `Services/HotkeyService.swift` | Global hotkey registration (Carbon) |
| `Services/ScreenCaptureService.swift` | Interactive screenshot capture |
| `Views/OverlayManager-3.swift` | Floating overlay: loading, streaming response, error display |
| `Views/PaywallView.swift` | Dual-card paywall (free + referral / paid) |
| `Views/SetupWizardView.swift` | First-launch wizard (600×520pt), screen recording permission |
| `Views/SettingsView.swift` | Settings panel (420×410pt), tabbed |
| `Services/AuthViews.swift` | Upgrade prompt, account creation/login, checkout polling |
| `Utils/KeychainHelper.swift` | Keychain read/write/delete (service: `ai.presto.app`) |

---

## App States (`AppState` enum)
| State | Condition | Can Analyze |
|-------|-----------|-------------|
| `.anonymous` | No device ID yet | No |
| `.freeActive` | Device has queries remaining (1–5) | Yes |
| `.freeExhausted` | 5 device queries used, no paid/referral | No |
| `.referralActive` | Referral reward active (30 days) | Yes |
| `.paid` | Valid JWT + active subscription | Yes (50/day; 200 for admins) |

State initialized on launch: JWT validity → fallback to device status. Backend is source of truth.

---

## Monetization

### Free Tier
- 5 lifetime queries per device (tracked by UUID in Keychain)
- No account needed

### Paid (Polar)
- Monthly subscription via Polar hosted checkout
- Early bird: $5.99/mo, post-launch: $10.99/mo (sync with `app_config.monthly_price_display`)

### Referral System (Device-Based)
1. User exhausts free queries → paywall shown
2. Clicks "Copy Link" → creates `PRESTO-XXXXXX` code (6 alphanumeric chars)
3. Friend enters code in onboarding → claimed
4. Friend completes 1 analysis → auto-qualified
5. After 3 qualified friends → 30 days free for referrer
- Constants: `REFERRAL_QUALIFIED_NEEDED = 3`, reward = 30 days

### Promo Codes
- Admin-generated, grant free days
- Validated: `prefix` (A-Z0-9, max 10 chars), `free_days` (1–365), `max_uses` (1–10000)

---

## Payment Flow
```
1. User taps "Subscribe" → AccountViewController (email/password)
2. After registration → JWT saved → GET /api/billing/checkout-url
3. Polar checkout opens in browser
4. CheckoutStatusView polls GET /api/auth/status every 3s (5 min timeout)
5. Polar webhook fires → backend sets subscription_status="active"
6. Poll returns state="paid" → AppState = .paid
```

---

## Data Flow: Screenshot Analysis
```
1. Cmd+Shift+X → AppStateManager.canAnalyze check
2. ScreenCaptureService.captureInteractive() → base64 PNG
3. ImageCompressor.compress() → 1024px max, JPEG 80%
4. POST /api/analyze (SSE stream)
5. SSEStreamDelegate.onChunk → overlayManager.appendChunk()
6. [DONE] → onComplete(queriesRemaining, state) → update AppStateManager
```

---

## Backend API Endpoints

### Auth
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/auth/register` | None | Register, returns tokens |
| POST | `/api/auth/login` | None | Login, returns tokens |
| POST | `/api/auth/refresh` | None | Token rotation |
| GET | `/api/auth/status` | Bearer | Returns `{state, email}` |

### Core
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/analyze` | Optional | Main SSE streaming endpoint |
| POST | `/api/query` | Bearer | Legacy alias for /api/analyze |
| GET | `/api/device/status` | None | Device query status |
| GET | `/api/user/profile` | Bearer | Profile + referral info |

### Billing (Polar)
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/billing/checkout-url` | Optional | Polar checkout URL |
| POST | `/api/subscription/checkout` | Bearer | Checkout for logged-in user |
| POST | `/api/webhooks/polar` | Signature | Polar webhook handler |

### Referral
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/referral/paywall` | None | Paywall state for device |
| POST | `/api/referral/code` | None | Create referral code |
| POST | `/api/referral/claim` | None | Claim referral code |
| GET | `/api/referral/status` | None | Referral progress |

### Admin
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/admin/stats` | Dashboard stats |
| GET | `/api/admin/users` | Paginated user list |
| GET | `/api/admin/users/{id}` | User detail + usage |
| POST | `/api/admin/set-premium` | Grant premium (1–3650 days) |
| POST | `/api/admin/promo/create` | Generate promo codes |
| POST | `/api/admin/promo/deactivate/{code}` | Deactivate promo |
| GET | `/api/admin/promo/list` | List promos |
| POST | `/api/admin/reset-device` | Reset device (testing) |
| GET | `/health` | Health check |

---

## Database Models (8 tables)
- **User** — email, password_hash, referral_code, polar_customer_id, subscription_status/ends_at, query counters
- **Device** — UUID (client-generated), queries_used, linked_user_id
- **QueryLog** — per-query log: tokens, cost, response time, status
- **PromoCode** / **PromoRedemption** — promo code management
- **ReferralCode** — device-based referral codes (PRESTO-XXXXXX)
- **ReferralClaim** — friend claims, qualified flag
- **ReferralReward** — 30-day reward after 3 qualifications
- **AppConfig** — runtime key-value config (monthly_price_display, free_device_queries, etc.)

---

## Auth Token Storage (Keychain)
| Key | Purpose | Expiry |
|-----|---------|--------|
| `presto.device_id` | Anonymous device UUID | Permanent |
| `presto.access_token` | JWT auth token | 24 hours |
| `presto.refresh_token` | Refresh token | 30 days |

Auto-refresh on 401: APIService retries once after refreshing token.

---

## Environment Variables (Railway)
| Variable | Required | Purpose |
|----------|----------|---------|
| `JWT_SECRET` | Yes | JWT signing (must be strong) |
| `ANTHROPIC_API_KEY` | Yes | Claude API key |
| `DATABASE_URL` | No | PostgreSQL (defaults to SQLite) |
| `POLAR_ACCESS_TOKEN` | Yes | Polar API token |
| `POLAR_PRODUCT_ID` | Yes | Polar product UUID |
| `POLAR_WEBHOOK_SECRET` | Yes | Webhook signature verification |
| `POLAR_SUCCESS_URL` | No | Post-checkout redirect |
| `ADMIN_EMAILS` | No | Comma-separated admin emails |
| `ALLOWED_ORIGINS` | No | CORS origins |

---

## Security (Current State)
- JWT HS256 with strong secret (rejects weak defaults)
- Bcrypt password hashing
- Password: min 8 chars, requires uppercase + lowercase + number
- Polar webhook signature verification
- Security headers: HSTS, X-Frame-Options, X-Content-Type-Options, XSS-Protection
- CORS: restricted origins, methods (`GET, POST, OPTIONS`), headers
- App sandboxed, HTTP only allowed to localhost (DEBUG)
- Release builds: hardcoded backend URL (no UserDefaults override)
- Device ID abuse: max 10 per IP/day (in-memory tracker)
- Prompt snippets redacted in QueryLog
- Generic error messages (no exception leakage to clients)
- Checkout endpoint: uniform "Access denied" errors (no email enumeration)

---

## SSE Response Format
```
data: {"delta": "text chunk", "queries_remaining": 3, "state": "free_active"}
data: {"queries_remaining": 2, "state": "free_active"}   ← final state
data: [DONE]
```

---

## Config Values
| Setting | Value |
|---------|-------|
| Free device queries | 5 lifetime |
| Paid daily limit | 50/day (200 admin) |
| Referral reward | 30 days after 3 qualified |
| Image max size | 1024px, JPEG 80% |
| Claude model | claude-haiku-4-5-20251001 |
| Max tokens | 2,048 |
| Request timeout | 300s |

---

*Last updated: March 9, 2026*
