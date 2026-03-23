# Phase 4: Account & Security — Execution Plan

**Goal:** Add password reset, proper session management/logout, and email validation so users aren't locked out of accounts.

**Key files:** `Presto backend/main.py`, `Presto backend/requirements.txt`, `PrestoAI/Services/APIService.swift`, `PrestoAI/Services/AuthViews.swift`, `PrestoAI/Views/AppStateManager.swift`

---

## Architecture

**Password reset flow:**
1. User enters email on client → `POST /api/auth/request-reset` → backend generates a 6-digit code, stores hashed version with 15-min expiry
2. Backend sends code via Resend (email API) to user's email
3. User enters code + new password on client → `POST /api/auth/reset-password` → backend verifies code, updates password hash

**Why Resend:** Simple API (single HTTP call, no SMTP), generous free tier (100 emails/day), single dependency (`resend` Python package). No SMTP config needed.

**Logout:** Backend endpoint blacklists the refresh token. Client clears Keychain tokens.

**Email validation:** Already partially done (email-validator package in requirements.txt, regex in Swift). Tighten both sides.

---

## Tasks

### Task 1: Backend — Add Resend email service + password reset endpoints

**What:** Add two new endpoints and email sending capability.

**Files:** `Presto backend/main.py`, `Presto backend/requirements.txt`

**Changes to requirements.txt:**
- Add `resend` package

**Changes to main.py:**

**1a. Add imports and config:**
```python
import resend
import hashlib

resend.api_key = os.getenv("RESEND_API_KEY", "")
```

**1b. Add reset code storage (in-memory with expiry, like device ID tracker):**
```python
# Password reset codes: {email: {"code_hash": str, "expires": datetime}}
reset_codes: dict[str, dict] = {}
```

**1c. Add request models:**
```python
class RequestResetRequest(BaseModel):
    email: str

class ResetPasswordRequest(BaseModel):
    email: str
    code: str
    newPassword: str
```

**1d. Add POST /api/auth/request-reset endpoint:**
```python
@app.post("/api/auth/request-reset")
def request_reset(req: RequestResetRequest, db: Session = Depends(get_db)):
    # Always return success (don't reveal if email exists)
    user = db.query(User).filter(User.email == req.email).first()
    if not user:
        return {"message": "If an account exists, a reset code has been sent."}

    # Generate 6-digit code
    code = f"{secrets.randbelow(1000000):06d}"
    code_hash = hashlib.sha256(code.encode()).hexdigest()
    reset_codes[req.email.lower()] = {
        "code_hash": code_hash,
        "expires": datetime.utcnow() + timedelta(minutes=15),
    }

    # Send email via Resend
    if resend.api_key:
        try:
            resend.Emails.send({
                "from": "Presto AI <noreply@get-prestoai.com>",
                "to": req.email,
                "subject": "Your Presto AI password reset code",
                "html": f"<p>Your password reset code is: <strong>{code}</strong></p><p>This code expires in 15 minutes.</p><p>If you didn't request this, ignore this email.</p>",
            })
        except Exception as e:
            print(f"[PRESTO.AI] Failed to send reset email: {e}")

    return {"message": "If an account exists, a reset code has been sent."}
```

**1e. Add POST /api/auth/reset-password endpoint:**
```python
@app.post("/api/auth/reset-password")
def reset_password(req: ResetPasswordRequest, db: Session = Depends(get_db)):
    email_lower = req.email.lower()
    stored = reset_codes.get(email_lower)

    if not stored or datetime.utcnow() > stored["expires"]:
        raise HTTPException(400, "Invalid or expired reset code")

    code_hash = hashlib.sha256(req.code.encode()).hexdigest()
    if code_hash != stored["code_hash"]:
        raise HTTPException(400, "Invalid or expired reset code")

    # Validate new password
    if len(req.newPassword) < 8:
        raise HTTPException(400, "Password must be at least 8 characters")
    if not re.search(r'[A-Z]', req.newPassword):
        raise HTTPException(400, "Password must contain at least one uppercase letter")
    if not re.search(r'[a-z]', req.newPassword):
        raise HTTPException(400, "Password must contain at least one lowercase letter")
    if not re.search(r'[0-9]', req.newPassword):
        raise HTTPException(400, "Password must contain at least one number")

    user = db.query(User).filter(User.email == req.email).first()
    if not user:
        raise HTTPException(400, "Invalid or expired reset code")

    user.password_hash = bcrypt.hashpw(req.newPassword.encode(), bcrypt.gensalt()).decode()
    db.commit()

    # Clean up used code
    del reset_codes[email_lower]

    return {"message": "Password reset successfully"}
```

**Environment variable needed:** `RESEND_API_KEY` on Railway.

**Verify:** `POST /api/auth/request-reset` with valid email → returns success message, email received. `POST /api/auth/reset-password` with correct code → password updated, can login with new password.

---

### Task 2: Backend — Add logout endpoint with token blacklist

**What:** Add `POST /api/auth/logout` that blacklists the refresh token so it can't be reused.

**Files:** `Presto backend/main.py`

**Changes:**

**2a. Add in-memory token blacklist (with TTL cleanup):**
```python
# Blacklisted refresh tokens: {token_hash: expiry_datetime}
token_blacklist: dict[str, datetime] = {}

def is_blacklisted(token: str) -> bool:
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    entry = token_blacklist.get(token_hash)
    if not entry:
        return False
    if datetime.utcnow() > entry:
        del token_blacklist[token_hash]  # Cleanup expired
        return False
    return True
```

**2b. Add logout endpoint:**
```python
class LogoutRequest(BaseModel):
    refreshToken: str

@app.post("/api/auth/logout")
def logout(req: LogoutRequest):
    try:
        payload = jwt.decode(req.refreshToken, SECRET_KEY, algorithms=["HS256"])
        exp = datetime.fromtimestamp(payload["exp"])
        token_hash = hashlib.sha256(req.refreshToken.encode()).hexdigest()
        token_blacklist[token_hash] = exp
    except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
        pass  # Token already expired/invalid — effectively logged out
    return {"message": "Logged out"}
```

**2c. Update refresh endpoint to check blacklist:**
In the existing `refresh_token()` function, add at the top:
```python
if is_blacklisted(req.refreshToken):
    raise HTTPException(401, "Token has been revoked")
```

**Verify:** Login → get tokens → POST /api/auth/logout with refresh token → try refresh → get 401 "Token has been revoked".

---

### Task 3: Client — Add password reset flow UI + API calls

**What:** Add password reset screens and API integration on the Swift client.

**Files:** `PrestoAI/Services/APIService.swift`, `PrestoAI/Services/AuthViews.swift`

**Changes to APIService.swift:**

Add two new methods:
```swift
func requestPasswordReset(email: String) async throws {
    let url = URL(string: "\(baseURL)/api/auth/request-reset")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["email": email])
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw APIError.serverError
    }
}

func resetPassword(email: String, code: String, newPassword: String) async throws {
    let url = URL(string: "\(baseURL)/api/auth/reset-password")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: String] = ["email": email, "code": code, "newPassword": newPassword]
    request.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.serverError }
    if http.statusCode != 200 {
        if let err = try? JSONDecoder().decode([String: String].self, from: data),
           let detail = err["detail"] {
            throw APIError.custom(detail)
        }
        throw APIError.serverError
    }
}

func logout(refreshToken: String) async throws {
    let url = URL(string: "\(baseURL)/api/auth/logout")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["refreshToken": refreshToken])
    let _ = try? await URLSession.shared.data(for: request)
    // Fire-and-forget — even if this fails, client clears local tokens
}
```

**Changes to AuthViews.swift:**

Add a `PasswordResetView` with 2 states:
1. **Enter email** → calls `requestPasswordReset()` → shows "Check your email"
2. **Enter code + new password** → calls `resetPassword()` → shows success, dismisses

Add a "Forgot password?" link in `AccountView` below the sign-in button that shows the reset flow.

Add a `PasswordResetController` window controller (like existing `AccountViewController`).

**Verify:** Open account view → tap "Forgot password?" → enter email → receive code → enter code + new password → password updated → can sign in with new password.

---

### Task 4: Client — Wire logout to clear all auth state

**What:** Update the sign-out flow to call the backend logout endpoint before clearing local state.

**Files:** `PrestoAI/Views/AppStateManager.swift`, `PrestoAI/Services/APIService.swift`

**Changes to AppStateManager.swift:**

Update the existing `signOut()` method to:
1. Call `APIService.shared.logout(refreshToken:)` with the stored refresh token
2. Then clear all Keychain tokens (access + refresh)
3. Reset state to `.freeExhausted`

```swift
func signOut() {
    // Invalidate refresh token on backend
    if let refreshToken = KeychainHelper.read(key: "presto.refresh_token") {
        Task {
            try? await APIService.shared.logout(refreshToken: refreshToken)
        }
    }
    // Clear local auth state
    KeychainHelper.delete(key: "presto.access_token")
    KeychainHelper.delete(key: "presto.refresh_token")
    jwt = nil
    currentState = .freeExhausted
}
```

**Verify:** Sign in → sign out → refresh token is blacklisted on backend → app shows free exhausted state → old refresh token can't be reused.

---

## Execution Order

1. **Task 1** — Backend password reset endpoints (independent)
2. **Task 2** — Backend logout endpoint (independent, can parallel with Task 1)
3. **Task 3** — Client password reset UI (depends on Task 1 being deployed)
4. **Task 4** — Client logout wiring (depends on Task 2)

Tasks 1+2 are backend-only. Tasks 3+4 are client-only. Each pair can be done in parallel.

---

## Environment Setup Required

Before deploying:
1. Sign up at [resend.com](https://resend.com) (free tier: 100 emails/day)
2. Verify domain `get-prestoai.com` in Resend dashboard
3. Add `RESEND_API_KEY` environment variable to Railway

---

## Testing Checklist

- [ ] `POST /api/auth/request-reset` with valid email → 200, email sent with 6-digit code
- [ ] `POST /api/auth/request-reset` with invalid email → 200 (no email enumeration)
- [ ] `POST /api/auth/reset-password` with correct code → 200, password updated
- [ ] `POST /api/auth/reset-password` with wrong code → 400
- [ ] `POST /api/auth/reset-password` after 15 min → 400 (expired)
- [ ] `POST /api/auth/reset-password` with weak password → 400 with validation message
- [ ] `POST /api/auth/logout` → refresh token blacklisted
- [ ] `POST /api/auth/refresh` with blacklisted token → 401
- [ ] Client: "Forgot password?" link visible on sign-in screen
- [ ] Client: full reset flow works end-to-end
- [ ] Client: sign out calls backend logout then clears Keychain
- [ ] Client: after sign out, old tokens don't work
