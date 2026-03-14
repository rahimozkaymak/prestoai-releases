# User Flow Implementation Summary

## Overview
Implemented complete user authentication, free tier management, and subscription flow for Presto.AI macOS app.

## Files Created

### 1. **AppStateManager.swift**
- **AppState enum** with 4 states: `.anonymous`, `.freeActive`, `.freeExhausted`, `.paid`
- Device ID management (UUID stored in Keychain under `presto.device_id`)
- JWT token management (stored in Keychain under `presto.jwt`)
- State initialization and validation on app launch
- Query tracking and state updates after each analysis
- `canAnalyze` property to check if user can perform analysis

### 2. **AuthViews.swift**
Contains all UI components for the authentication flow:
- **UpgradePromptView**: Shown when free tier exhausted
- **AccountView**: Email/password form with sign in/register toggle
- **CheckoutStatusView**: Polling view during checkout process
- **Window Controllers**: `UpgradePromptController`, `AccountViewController`, `CheckoutViewController`

## Files Modified

### 1. **APIService.swift**
Added/Updated:
- `DeviceStatus`, `AuthStatus`, `AnalyzeResponse` structs
- `sendScreenshot()` now includes:
  - Device ID header (`X-Device-ID`)
  - `onComplete` callback with queries remaining and state
  - Changed endpoint from `/api/query` to `/api/analyze`
- New methods:
  - `checkDeviceStatus(deviceID:)` - Check remaining queries for device
  - `validateAuth(token:)` - Validate JWT token
  - `getCheckoutURL(email:deviceID:)` - Get LemonSqueezy checkout URL
- Updated `SSEStreamDelegate` to track and return final state

### 2. **PrestoAIApp.swift (AppDelegate)**
Added:
- Window controller properties for auth flows
- Updated `setupMenuBar()`:
  - Shows remaining queries in menu for free tier users
  - Shows "Sign Out" option for paid users
  - Dynamically updates based on current state
- Updated `captureScreenshot()`:
  - Checks `canAnalyze` before capture
  - Shows upgrade prompt if limit reached
  - Updates app state after successful query
- New methods:
  - `signOut()` - Clear JWT, set state to exhausted
  - `showUpgradePrompt()` - Display upgrade UI
  - `showAccountCreation()` - Display account creation/login
  - `showCheckout()` - Handle checkout flow
  - `showSuccessMessage()` - Success confirmation

## User Flow Diagram

```
┌─────────────┐
│ App Launch  │
└──────┬──────┘
       │
       ├─ Has JWT? ──YES──> Validate with backend
       │                    ├─ Valid ──> State = .paid
       │                    └─ Invalid ─> Clear JWT, check device
       │
       └─ NO ──> Check device status
                 ├─ Queries > 0 ──> State = .freeActive
                 └─ Queries = 0 ──> State = .freeExhausted

┌──────────────────┐
│ User presses     │
│ Cmd+Shift+X      │
└────────┬─────────┘
         │
         ├─ State = .paid ──────────> Perform analysis
         │
         ├─ State = .freeActive ────> Perform analysis
         │                             └─> Update queries remaining
         │
         └─ State = .freeExhausted ─> Show upgrade prompt
                                       ├─ "Create Account"
                                       ├─ "Promo Code"
                                       └─ "Not now"

┌─────────────────────┐
│ Account Creation    │
└──────────┬──────────┘
           │
           ├─ Email + Password
           │  └─> POST /api/auth/register or /api/auth/login
           │       └─> Receive JWT
           │
           └─> Trigger Checkout
                ├─> GET /api/billing/checkout-url
                ├─> Open URL in browser
                ├─> Poll GET /api/auth/status (every 3s)
                └─> On payment complete:
                    ├─ Save JWT
                    ├─ State = .paid
                    └─ Show success message
```

## Backend Endpoints Required

### 1. **GET /api/device/status**
Query params: `device_id`
Headers: `X-Device-ID`
Response:
```json
{
  "queriesRemaining": 3,
  "state": "free_active"
}
```

### 2. **POST /api/analyze**
Body: `{ "image": "base64...", "prompt": "...", "media_type": "image/jpeg", "device_id": "uuid" }`
Headers: 
- `X-Device-ID: <device_id>`
- `Authorization: Bearer <jwt>` (optional, if logged in)

Streaming response (SSE):
```
data: {"delta": "text chunk", "queries_remaining": 2, "state": "free_active"}
data: [DONE]
```

### 3. **GET /api/auth/status**
Headers: `Authorization: Bearer <jwt>`
Response:
```json
{
  "state": "paid",
  "token": "jwt_token",
  "email": "user@example.com"
}
```

### 4. **GET /api/billing/checkout-url**
Query params: `email`, `device_id`
Response:
```json
{
  "checkout_url": "https://lemonsqueezy.com/checkout/..."
}
```

### 5. **POST /api/auth/register**
Body: `{ "email": "user@example.com", "password": "password", "device_id": "uuid" }`
Response: Same as login (returns JWT)

### 6. **POST /api/auth/login**
Body: `{ "email": "user@example.com", "password": "password" }`
Response:
```json
{
  "accessToken": "jwt_token",
  "refreshToken": "refresh_token"
}
```

## Key Features

### Device ID
- Generated once on first launch
- Stored in Keychain (never deleted)
- Sent with every request
- Backend tracks 5 lifetime free queries per device

### JWT Management
- Stored in Keychain
- Validated on app launch
- Attached to requests when available
- Can be cleared via "Sign Out"

### State-Driven UI
- Menu bar dynamically shows:
  - Free queries remaining (free tier)
  - Sign out option (paid tier)
- Capture action checks state before proceeding
- Upgrade prompt triggered automatically when limit hit

### No Local Query Tracking
- Always trust backend for query count
- State updated after each successful analysis
- No local counters or UserDefaults

## Testing Checklist

- [ ] Fresh install generates device ID
- [ ] Device ID persists across launches
- [ ] Free tier allows 5 analyses
- [ ] 6th attempt shows upgrade prompt
- [ ] Account creation flow works
- [ ] Sign in flow works
- [ ] Checkout URL opens in browser
- [ ] Polling detects payment completion
- [ ] JWT saved after payment
- [ ] Paid users have unlimited access
- [ ] Menu bar updates based on state
- [ ] Sign out clears JWT but keeps device ID
- [ ] After sign out, user sees free tier exhausted state

## Notes

- **No changes to capture/overlay/hotkey logic** as requested
- All existing functionality preserved
- State management centralized in `AppStateManager`
- UI is native SwiftUI (no web views for auth)
- Keychain used for secure storage (not UserDefaults)
- Backend is source of truth for query limits
