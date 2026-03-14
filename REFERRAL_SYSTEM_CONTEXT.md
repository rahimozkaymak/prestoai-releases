# Referral & Paywall System — Implementation Context

> Created: 2026-03-09
> Purpose: Full context for the device-based referral system and paywall, so any future session can understand, modify, or debug it.

---

## Overview

After 5 free lifetime analyses, users see a **PaywallView** with two options:
1. **Subscribe** — goes through account creation + Polar checkout (existing flow)
2. **Refer 3 friends** — one-time offer; each friend must complete an analysis to "qualify"; once 3 qualify, referrer gets 30 days free access

After the referral reward is used or expired, only the subscribe path remains (referral card disappears).

---

## Architecture

### Flow Summary

```
User exhausts 5 free queries
    → GET /api/referral/paywall?device_id=X
    → PaywallView shown (dual or single card based on can_use_referral)

Referral path:
    → User clicks "Copy Link" → POST /api/referral/code (creates PRESTO-XXXXXX)
    → Friend installs app, enters code in onboarding → POST /api/referral/claim
    → Friend completes an analysis → qualify_referred_device() auto-called
    → After 3 qualified friends → ReferralReward created (30 days)
    → Referrer can now analyze again (checked in /analyze)

Subscribe path:
    → Opens account creation → Polar checkout (unchanged from before)
```

### Key Constants

- `FREE_DEVICE_QUERIES = 5` — lifetime free analyses per device
- `REFERRAL_QUALIFIED_NEEDED = 3` — friends needed to earn reward
- Reward duration: 30 days (hardcoded in `qualify_referred_device()`)
- Referral codes: `PRESTO-` + 6 uppercase alphanumeric chars

---

## Backend Changes

### File: `/Volumes/T7/PrestoAI/Presto backend/main.py`

### New Models (after PromoRedemption, before `create_all()`)

```python
ReferralCode       # referrer_device_id (unique), code (unique)
ReferralClaim      # code (FK), referred_device_id (unique), qualified, qualified_at
ReferralReward     # referrer_device_id (unique), granted_at, expires_at
AppConfig          # key (PK), value — stores monthly_price_display, polar_checkout_base_url
```

Tables are created via `Base.metadata.create_all()`. After that, `app_config` is seeded with defaults.

### New Helper Functions

- `gen_device_referral()` — generates `PRESTO-` + 6 chars (shorter than user referral codes which are 10 chars)
- `qualify_referred_device(device_id, db)` — called after every successful analysis:
  - Finds unqualified claim for this device, marks it qualified
  - Counts qualified claims for that referral code's referrer
  - If count >= 3 and no reward exists, creates ReferralReward (expires in 30 days)

### New Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/referral/paywall?device_id=X` | GET | None | Returns paywall state: `can_use_referral`, `referral_code`, `referral_status`, `subscribe_price`, `checkout_url`, `reward_expires_at` |
| `/api/referral/code` | POST | None | Body: `{device_id}`. Get or create referral code. Returns `{code, share_url}` |
| `/api/referral/claim` | POST | None | Body: `{device_id, code}`. Claim a referral. Validates: code exists, no self-referral, no double-claim (UNIQUE on referred_device_id) |
| `/api/referral/status?device_id=X` | GET | None | Returns `{qualified_count, needed, redeemed, expires_at}` |
| `/api/admin/reset-device?device_id=X` | POST | Admin | Resets device to fresh state: zero queries, clears all referral data. Requires `ADMIN_EMAILS` env var. |

### Modified: `/api/analyze` Access Chain (line ~647)

**Before:** 403 with "Free queries exhausted. Please subscribe."

**After:**
```python
if device.queries_used >= FREE_DEVICE_QUERIES:
    reward = db.query(ReferralReward).filter_by(referrer_device_id=device_id).first()
    if reward and reward.expires_at > datetime.utcnow():
        pass  # Referral reward active, allow
    else:
        raise HTTPException(403, detail="no_access")
```

After successful streaming, calls:
```python
qualify_referred_device(device_id, db)
```

### Removed Dead Code

- `REFERRALS_FOR_FREE_MONTH = 2` constant (was for old user-account referral system)
- `free_months_earned` increment in `/api/auth/register` (the `ref.referral_count += 1` still remains for admin dashboard tracking)

---

## Frontend Changes

### New File: `/Volumes/T7/PrestoAI/PrestoAI/Views/PaywallView.swift`

Contains:
- `PaywallInfo` struct — data model from backend
- `PaywallView` — SwiftUI view with two layouts:
  - **Dual layout** (`canUseReferral == true`): Subscribe card + Referral card side by side
  - **Subscribe-only** (`canUseReferral == false`): Just the subscribe card centered
- `PaywallController` — NSPanel-based controller using `makePrestoPanel()` pattern

Design: Dark theme matching `WZ.bg` (#0A0A0A), progress dots for referral count, "Copy Link" button copies `https://prestoai.app/r/PRESTO-XXXXXX` to clipboard.

### Modified: `/Volumes/T7/PrestoAI/PrestoAI/Services/APIService.swift`

**New methods:**
- `getPaywallInfo(deviceID:) async throws -> PaywallInfo`
- `createReferralCode(deviceID:) async throws -> ReferralCodeResponse`
- `claimReferralCode(deviceID:, code:) async throws`

**New error case:**
- `APIError.noAccess` — for the new `"no_access"` 403 detail

**Modified:**
- `handleResponse()` — detects `"no_access"` in 403 body, throws `.noAccess`
- SSE delegate 403 handler — now throws `.noAccess` instead of `.freeExhausted`
- `APIError` conforms to `Equatable` (needed for `== .noAccess` comparison)

### Modified: `/Volumes/T7/PrestoAI/PrestoAI/PrestoAIApp.swift`

- Added `paywallController: PaywallController?` property
- `captureScreenshot()` now calls `showPaywall()` instead of `showUpgradePrompt()` when `!canAnalyze`
- New `showPaywall()` method: calls `GET /api/referral/paywall`, creates `PaywallController`, falls back to `showUpgradePrompt()` on error
- `refreshMenuState()` handles `.referralActive` case
- SSE `onError` callback catches `.noAccess` and triggers `showPaywall()` instead of showing error overlay

### Modified: `/Volumes/T7/PrestoAI/PrestoAI/Views/AppStateManager.swift`

- New enum case: `AppState.referralActive`
- New property: `referralRewardActive: Bool`
- New method: `checkReferralReward()` — calls `getPaywallInfo()`, parses ISO8601 expiry, sets state to `.referralActive` if reward is valid
- `initializeState()` — when device status shows 0 remaining, calls `checkReferralReward()` before marking as `.freeExhausted`
- `canAnalyze` returns `true` for `.referralActive`

### Modified: `/Volumes/T7/PrestoAI/PrestoAI/Views/SetupWizardView.swift`

Added to `doneContent` (step 2 of onboarding), after the menu bar hint:
- "Have a referral code?" link → reveals text field + "Apply" button
- `submitReferralCode()` calls `POST /api/referral/claim`
- Inline success ("Referral code applied!") or error message

### Modified: `/Volumes/T7/PrestoAI/PrestoAI/Views/SettingsView.swift`

- `accountSubtitle` switch handles `.referralActive` → "Referral reward active"

---

## Existing Patterns Reused

- `WZ` color enum from `SetupWizardView.swift` — dark theme colors
- `makePrestoPanel(size:title:)` from `PrestoAIApp.swift` — floating NSPanel factory
- `get_or_create_device()` from `main.py` — device lookup/creation
- `UpgradePromptController` pattern — reference for `PaywallController`

---

## Infrastructure

- **Backend repo:** `github.com/rahimozkaymak/prestoai-backend` → auto-deploys to Railway
- **Production URL:** `https://prestoai-backend-production.up.railway.app`
- **Admin access:** Set `ADMIN_EMAILS=rahimozkaymak@gmail.com` in Railway env vars
- **Database:** PostgreSQL on Railway (tables auto-created via `create_all()`)

---

## Testing Checklist

1. Exhaust 5 free queries → paywall appears with both cards (subscribe + referral)
2. Click "Copy Link" → creates referral code, copies `https://prestoai.app/r/PRESTO-XXXXXX`
3. Subscribe button → opens account creation flow
4. Dismiss paywall (X) → next Cmd+Shift+X shows paywall again
5. After referral reward used → only subscribe card shown
6. Onboarding: enter valid referral code → "Referral code applied!"
7. Onboarding: enter invalid code → inline error
8. Self-referral blocked, double-claim blocked (UNIQUE constraint)
9. Reset device for retesting: `POST /api/admin/reset-device?device_id=X` (requires admin JWT)

### How to Reset a Device for Testing

```bash
# 1. Get device ID
security find-generic-password -a "presto.device_id" -w

# 2. Get fresh JWT (refresh if expired)
REFRESH=$(security find-generic-password -a "presto.refresh_token" -w)
curl -s -X POST "https://prestoai-backend-production.up.railway.app/api/auth/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refreshToken\": \"$REFRESH\"}"

# 3. Reset (use accessToken from step 2)
curl -s -X POST "https://prestoai-backend-production.up.railway.app/api/admin/reset-device?device_id=DEVICE_ID" \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json"
```

---

## Not Yet Implemented

- **Web referral landing page** (`prestoai.app/r/PRESTO-XXXXXX`) — static HTML page showing referral code, auto-copy, download link. Listed as step 9 in the plan but not built yet.
