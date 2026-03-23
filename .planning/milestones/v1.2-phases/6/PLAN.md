# Phase 6: Client UX Polish — Execution Plan

**Goal:** Handle edge cases gracefully — offline mode, retry logic, compression fallback, dynamic pricing.

---

## Tasks

### Task 1: Offline/unreachable backend handling (R6.1)
Add a connectivity check in AppStateManager. Show clear "offline" overlay message instead of silent denial.

### Task 2: Retry logic for transient 5xx errors (R6.3)
In APIService `get()` and `post()`, retry once on 500-599 status codes before throwing.

### Task 3: Image compression fallback (R6.4)
When JPEG compression fails, fall back to resized PNG instead of sending the original full-size image.

### Task 4: Replace hardcoded pricing (R6.5)
Replace "$5.99/month" in SettingsView and AuthViews with dynamic value from PaywallInfo or a cached config.

### Task 5: Usage warning near daily limit (R6.2)
Show a warning in the overlay when paid users approach 40/50 daily queries.
