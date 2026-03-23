# Phase 5: Backend Hardening — Execution Plan

**Goal:** Make the backend production-grade: structured logging, webhook reliability, dead code cleanup, and N+1 query fix.

**Key file:** `Presto backend/main.py`

**Note:** R5.1 (Alembic migrations) is deferred. The backend uses `create_all()` which works fine as long as you don't need to modify existing columns. Alembic is high-effort/low-urgency — we'll add it when the next schema change requires it.

---

## Tasks

### Task 1: Replace all print() with structured logger

**What:** Replace all `print(f"[PRESTO.AI]...")` calls with proper `logger.info/warning/error` calls. The `logger` is already created (line 19) but barely used.

**File:** `Presto backend/main.py`

**Changes:**

Replace these print statements with logger calls:
- Line 545: `print(f"[PRESTO.AI] Failed to send reset email: {e}")` → `logger.error(f"Failed to send reset email: {e}")`
- Line 625-627: Streaming query info prints → `logger.info(f"Streaming query from {label}: image={len(req.image):,} chars, prompt={req.prompt[:80]!r}")`
- Line 665: Error body print → `logger.error(f"Anthropic API error: {body[:300]}")`
- Line 669: Streaming start print → `logger.info("Streaming from Anthropic...")`
- Line 729-731: Token/cost/timing prints → `logger.info(f"Query complete: {inp_tok}in/{out_tok}out ${cost:.5f} {elapsed}ms")`

Also search for any other `print(` statements and convert them.

**Verify:** No `print(f"[PRESTO.AI]` statements remain. All logging goes through the `logger` object.

---

### Task 2: Fix Polar webhook error handling — proper HTTP codes + idempotency

**What:** The webhook currently returns `{"status": "user_not_found"}` with HTTP 200 when the user isn't found. This silently fails. Also add idempotency for `subscription.active` events (prevent double-extending subscription on webhook replay).

**File:** `Presto backend/main.py`

**Changes:**

**2a. Return 404 for user not found (line ~1416):**
Change:
```python
return {"status": "user_not_found"}
```
To:
```python
raise HTTPException(404, f"User not found for webhook {event_type}")
```

This makes Polar aware the webhook failed, so it can retry.

**2b. Add idempotency for subscription.active:**
Before extending `subscription_ends_at`, check if we already processed this event. Use the subscription ID + event type as a dedup key:

```python
if event_type == "subscription.active":
    # Idempotency: if subscription is already active and ends_at is in the future, skip
    if (target.subscription_status == "active"
        and target.subscription_ends_at
        and target.subscription_ends_at > now + timedelta(days=25)):
        logger.info(f"Polar webhook: subscription already active for {target.email}, skipping")
        db.commit()
        return {"status": "ok", "note": "already_active"}

    target.subscription_status = "active"
    if target.subscription_ends_at and target.subscription_ends_at > now:
        target.subscription_ends_at = target.subscription_ends_at + timedelta(days=30)
    else:
        target.subscription_ends_at = now + timedelta(days=30)
```

**Verify:** Webhook with unknown user → 404 (not 200). Replaying same `subscription.active` webhook → doesn't double-extend.

---

### Task 3: Remove dead free_months system

**What:** The `free_months_earned` and `free_months_used` columns exist but are never incremented (no code path sets `free_months_earned > 0`). The subscription check logic at line ~420 runs but can never trigger. Remove the dead code.

**File:** `Presto backend/main.py`

**Changes:**

**3a. Remove the free months check in `check_sub` (~line 420):**
Delete the block:
```python
if user.free_months_earned > user.free_months_used:
    ...
    user.free_months_used += 1
```

**3b. Remove free months from profile response (~line 842):**
Delete:
```python
"freeMonthsEarned": user.free_months_earned,
"freeMonthsAvailable": user.free_months_earned - user.free_months_used,
```

**3c. Keep the database columns** — removing columns without Alembic is risky. Just remove the code that references them.

**Verify:** No references to `free_months_earned` or `free_months_used` in code (columns remain in DB model definition for schema compatibility).

---

### Task 4: Fix N+1 query in promo listing endpoint

**What:** `GET /api/admin/promo/list` queries all promos, then for each promo makes a separate DB query for redemptions. Replace with a single joined query.

**File:** `Presto backend/main.py`

**Changes:**

Replace the entire `admin_list_promos` function (~line 1292-1320) with a single query that loads promos with their redemptions:

```python
@app.get("/api/admin/promo/list")
def admin_list_promos(user: User = Depends(require_admin), db: Session = Depends(get_db)):
    promos = db.query(PromoCode).order_by(PromoCode.created_at.desc()).all()
    promo_ids = [p.id for p in promos]

    # Single query for all redemptions across all promos
    all_redemptions = (
        db.query(PromoRedemption, User)
        .join(User, PromoRedemption.user_id == User.id)
        .filter(PromoRedemption.promo_code_id.in_(promo_ids))
        .all()
    ) if promo_ids else []

    # Group redemptions by promo_code_id
    redemptions_by_promo = {}
    for r, u in all_redemptions:
        redemptions_by_promo.setdefault(r.promo_code_id, []).append((r, u))

    result = []
    for p in promos:
        redemptions = redemptions_by_promo.get(p.id, [])
        result.append({
            "code": p.code,
            "free_days": p.free_days,
            "max_uses": p.max_uses,
            "times_used": p.times_used,
            "is_active": p.is_active,
            "created_at": p.created_at.isoformat() if p.created_at else None,
            "expires_at": p.expires_at.isoformat() if p.expires_at else None,
            "redeemed_by": [{
                "email": u.email,
                "user_id": u.id,
                "redeemed_at": r.redeemed_at.isoformat(),
                "total_queries": u.total_queries,
                "total_tokens": u.total_input_tokens + u.total_output_tokens,
                "last_active": u.last_active_at.isoformat() if u.last_active_at else None,
            } for r, u in redemptions],
        })
    return {"promos": result}
```

This reduces N+1 queries to exactly 2 queries regardless of promo count.

**Verify:** `/api/admin/promo/list` returns same data as before but with only 2 DB queries (check logs).

---

## Execution Order

All 4 tasks modify `main.py` but different sections. Execute sequentially:
1. **Task 1** — logging (scattered throughout)
2. **Task 2** — webhook fixes (lines ~1374-1449)
3. **Task 3** — dead code removal (lines ~420, ~842)
4. **Task 4** — N+1 fix (lines ~1292-1320)

---

## Testing Checklist

- [ ] No `print(f"[PRESTO.AI]` statements remain in main.py
- [ ] All logging uses `logger.info/warning/error`
- [ ] Polar webhook with unknown user returns 404 (not 200)
- [ ] Replaying subscription.active webhook doesn't double-extend
- [ ] No references to `free_months_earned`/`free_months_used` in code (columns stay)
- [ ] `/api/admin/promo/list` returns correct data
- [ ] Admin dashboard still works after all changes
- [ ] Health endpoint returns 200
