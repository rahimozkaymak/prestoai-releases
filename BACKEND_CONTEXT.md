# Presto AI — Backend Context

## Overview
Single-file FastAPI backend (`Presto backend/main.py`, ~1060 lines) powering the Presto AI macOS app. Hosted on Railway, auto-deploys from `main` branch on GitHub (`rahimozkaymak/prestoai-backend`).

The app lets users photograph/screenshot problems and get AI-powered solutions via Claude (Haiku 4.5). Backend handles auth, billing, usage tracking, and proxies requests to the Anthropic API with SSE streaming.

---

## Tech Stack
- **Framework:** FastAPI 0.135
- **Database:** PostgreSQL (prod via Railway) / SQLite (local dev)
- **ORM:** SQLAlchemy 2.0 (no Alembic yet — uses `create_all()`)
- **Auth:** JWT (PyJWT) + bcrypt password hashing
- **AI:** Anthropic Claude API (Haiku 4.5) via raw httpx streaming
- **Payments:** Polar (polar.sh) via `polar-sdk` — merchant of record
- **HTTP client:** httpx (async, connection-pooled via lifespan)

---

## Environment Variables (Railway)
| Variable | Purpose |
|---|---|
| `JWT_SECRET` | JWT signing key (required, must be strong) |
| `ANTHROPIC_API_KEY` | Claude API key |
| `DATABASE_URL` | PostgreSQL connection string |
| `POLAR_ACCESS_TOKEN` | Polar API token |
| `POLAR_PRODUCT_ID` | Polar product UUID (`d11f33c2-22ad-40da-955b-156124f583cd`) |
| `POLAR_WEBHOOK_SECRET` | Polar webhook signature secret |
| `POLAR_SUCCESS_URL` | Redirect after checkout |
| `ADMIN_EMAILS` | Comma-separated admin email list |
| `ALLOWED_ORIGINS` | CORS origins (default: presto.ai domains) |

---

## Database Models (5 tables)

### `users`
- `id` (UUID PK), `email` (unique, indexed), `password_hash`
- `referral_code` (unique), `referred_by` (FK→users), `referral_count`
- `polar_customer_id`, `subscription_id` — Polar references
- `subscription_status`: `"trial"` | `"active"` | `"expired"` | `"canceled"` | `"free"`
- `trial_ends_at`, `subscription_ends_at` — datetime boundaries
- `free_months_earned`, `free_months_used` — referral rewards
- `queries_today`, `last_query_date`, `total_queries` — usage counters
- `total_input_tokens`, `total_output_tokens` — cumulative token usage
- `redeemed_promo_code`, `created_at`, `last_active_at`

### `devices`
- `id` (client UUID PK), `queries_used`, `linked_user_id` (FK→users)
- Tracks anonymous free-tier usage (5 lifetime queries per device)

### `query_logs`
- Per-query record: `user_id`, `device_id`, `timestamp`, `input_tokens`, `output_tokens`, `model`, `prompt_snippet`, `response_time_ms`, `status`, `cost_usd`

### `promo_codes`
- `code` (unique), `created_by` (FK→users), `free_days`, `max_uses`, `times_used`, `is_active`, `expires_at`

### `promo_redemptions`
- Join table: `promo_code_id`, `user_id`, `redeemed_at`

---

## API Endpoints

### Auth
| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/api/auth/register` | None | Register (email+password), returns JWT pair |
| POST | `/api/auth/login` | None | Login, returns JWT pair |
| POST | `/api/auth/refresh` | None | Refresh token rotation |
| GET | `/api/auth/status` | JWT | Returns `{state: "paid"|"trial"|"expired"}` — Swift app polls this |

### Core
| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/api/analyze` | JWT or device_id | Main endpoint — streams Claude response via SSE |
| POST | `/api/query` | JWT | Legacy alias for `/api/analyze` |
| GET | `/api/device/status` | None | Check free queries remaining for device |
| GET | `/api/user/profile` | JWT | User profile + subscription info |

### Billing (Polar)
| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/api/billing/checkout-url` | JWT or device-linked | Creates Polar checkout, returns URL |
| POST | `/api/subscription/checkout` | JWT | Alternate checkout creation |
| POST | `/api/webhooks/polar` | Polar signature | Webhook receiver — activates/deactivates subs |

### Promo Codes
| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/api/promo/redeem` | JWT | Redeem promo code for free days |
| POST | `/api/admin/promo/create` | Admin | Generate promo codes |
| POST | `/api/admin/promo/deactivate/{code}` | Admin | Deactivate a code |
| GET | `/api/admin/promo/list` | Admin | List all promos + redemptions |

### Admin
| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/api/admin/stats` | Admin | Dashboard stats (users, queries, costs, daily breakdown) |
| GET | `/api/admin/users` | Admin | Paginated user list (sortable) |
| GET | `/api/admin/users/{user_id}` | Admin | User detail + usage history |
| POST | `/api/admin/set-premium` | Admin | Manually grant premium to a user |

### Health
| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | None | DB connectivity check |

---

## User Flow
1. Anonymous user gets 5 free queries per device (tracked by client UUID)
2. User registers → gets 7-day free trial
3. Trial expires → user hits paywall → app requests checkout URL
4. Backend creates Polar checkout session with user metadata
5. User pays on Polar's hosted page
6. Polar fires `subscription.active` webhook → backend sets `subscription_status = "active"`
7. Swift app polls `/api/auth/status` → gets `{state: "paid"}` → unlocks

## Subscription Status Logic
- **`active`** → full access
- **`canceled`** → access until `subscription_ends_at` (grace period)
- **`trial`** → access until `trial_ends_at`
- **`expired`** / **`free`** → no access (paywall)
- Free months from referrals are consumed automatically when checking subscription

---

## Key Behaviors
- **Rate limiting:** 50 queries/day per user (200 for admins), 5 lifetime per anonymous device
- **Device abuse protection:** Max 10 device IDs per IP per day (in-memory tracker)
- **SSE streaming:** Proxies Anthropic streaming API, yields `{delta, queries_remaining, state}` events
- **Token tracking:** Input/output tokens logged per query, costs calculated per model tier
- **Referral system:** Every 2 referrals = 1 free month earned
- **Promo codes:** Admin-created, configurable free days, max uses, expiry; prevents double-redemption
- **Webhook security:** All Polar webhooks verified via `polar_sdk.webhooks.validate_event()`

---

## Constants
```
CLAUDE_MODEL = "claude-haiku-4-5-20251001"
MAX_TOKENS = 2048
FREE_TRIAL_DAYS = 7
FREE_DEVICE_QUERIES = 5
REFERRALS_FOR_FREE_MONTH = 2
ALLOWED_MEDIA_TYPES = {"image/png", "image/jpeg", "image/gif", "image/webp"}
```

---

## Known TODOs
- Replace `create_all()` with Alembic migrations
- Device IDs are client-generated (spoofable) — move to server-generated
- In-memory IP tracker resets on deploy — consider Redis for persistence
