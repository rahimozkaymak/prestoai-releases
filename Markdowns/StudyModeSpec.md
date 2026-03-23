# Presto AI — Study Mode (Screen-Aware Assistant) Spec

## Overview

Study Mode transforms Presto AI from a reactive screenshot tool into a proactive, screen-aware assistant. When toggled on, Presto silently monitors the user's screen at a throttled interval, analyzes what they're doing via Claude API, and surfaces contextual suggestions in a non-intrusive corner notification. A persistent prompt box stays on screen for user-initiated queries with full session context.

This is NOT continuous surveillance. It's a user-initiated session with explicit start/stop, throttled capture, and local-first processing.

---

## Activation

| Trigger | Behavior |
|---|---|
| `Cmd+Shift+S` | Toggle Study Mode on/off |
| Menu bar icon click | Dropdown shows Study Mode toggle + session stats |
| First activation | Show one-time permission explainer overlay |

When activated:
1. Menu bar icon changes state (e.g., pulsing dot or different tint)
2. Persistent prompt box appears (bottom-right, draggable)
3. First silent capture fires after 3-second delay
4. Corner notification: "Study Mode active — I'll suggest help as you work"

When deactivated:
1. All local capture data cleared from memory
2. Prompt box dismissed
3. Session summary shown briefly: "45min session, helped with 3 tasks"

---

## Capture Pipeline (Client-Side, Swift)

### Screen Capture

```
Trigger: active window change OR timer (every 45 seconds of inactivity)
Method: CGWindowListCreateImage (already have Screen Recording permission)
Format: JPEG, 1024px max dimension, quality 0.6 (lower than Cmd+Shift+X since this is analysis-only)
Storage: In-memory only, never written to disk
Lifecycle: Discarded after API response received
```

### Smart Capture Throttling

Don't capture on every tick. Capture when something meaningful changes:

```swift
// Pseudocode for capture decision
struct CaptureDecision {
    var lastCaptureTime: Date
    var lastWindowTitle: String
    var lastAppName: String
    
    func shouldCapture(currentWindow: String, currentApp: String) -> Bool {
        // Always capture on window/app change
        if currentWindow != lastWindowTitle || currentApp != lastAppName {
            return true
        }
        // Capture on timer if >45s since last capture
        if Date().timeIntervalSince(lastCaptureTime) > 45 {
            return true
        }
        // Don't capture if user is typing (detected via keyboard event monitoring)
        if userIsActivelyTyping {
            return false
        }
        return false
    }
}
```

### Privacy Exclusions (Client-Side Filter)

Before sending ANY screenshot to the backend, the client checks the frontmost app:

```swift
let excludedApps = [
    "1Password", "Keychain Access", "System Preferences",
    "Messages", "Signal", "WhatsApp", "Telegram",
    "Safari" // Only if URL contains banking/health domains
]

let excludedWindowTitles = [
    "Private Browsing", "Incognito",
    "password", "login", "sign in", "bank"
]
```

If excluded: skip capture entirely, don't even take the screenshot. Show subtle indicator: "Paused — private app detected"

Users can also add apps to a personal exclusion list in Presto settings.

### Context Package (Sent to Backend)

```json
{
    "session_id": "uuid",
    "capture_id": "uuid",
    "timestamp": "2026-03-18T14:32:00Z",
    "app_name": "Google Chrome",
    "window_title": "ISE 340 - Homework 5 - Google Docs",
    "clipboard_text": "∫ sin(2x)dx from 0 to π",
    "image_base64": "<jpeg_data>",
    "session_context": {
        "duration_minutes": 12,
        "apps_visited": ["Chrome", "Preview", "Calculator"],
        "previous_suggestions": ["Offered help with integral", "Offered email reply"],
        "questions_asked": 1
    }
}
```

---

## Backend (FastAPI on Railway)

### New Endpoint: `POST /api/v1/study/analyze`

```python
@router.post("/api/v1/study/analyze")
async def analyze_screen(
    request: StudyAnalyzeRequest,
    user: User = Depends(get_current_user)
):
    # 1. Rate limit: max 2 requests/minute per user
    # 2. Check subscription (Study Mode = paid feature only)
    # 3. Build analysis prompt
    # 4. Call Claude API with vision
    # 5. Return structured suggestion
    # 6. Log session context (no image stored)
```

### Claude API Analysis Prompt

```
You are Presto AI, a proactive screen-aware assistant. The user has Study Mode 
enabled and has granted you permission to analyze their screen.

Current context:
- App: {app_name}
- Window: {window_title}  
- Clipboard: {clipboard_text}
- Session duration: {duration_minutes} minutes
- Previous suggestions this session: {previous_suggestions}

Analyze the screenshot and determine:

1. WHAT is the user doing? (1 sentence)
2. Are they STUCK on something? (yes/no + evidence)
3. Can you HELP with something specific? (be concrete)
4. SUGGESTION: Write a single, specific offer of help (max 15 words)
   Examples: "Want me to solve that integral?" / "I can draft a reply to John's email" / "Need help debugging that Python error?"
5. CONFIDENCE: How confident are you this is useful? (low/medium/high)
   - low = generic screen, nothing actionable
   - medium = can see what they're doing, might help
   - high = clear problem visible, specific help available

If confidence is LOW, respond with: {"action": "none"}
Do NOT suggest help for: private messages, banking, health records, social media browsing.

Respond in JSON only:
{
    "action": "suggest" | "none",
    "what_user_is_doing": "string",
    "suggestion_text": "string (max 15 words)",
    "suggestion_type": "solve" | "draft" | "explain" | "organize" | "review",
    "confidence": "low" | "medium" | "high",
    "follow_up_prompt": "string (what to send if user accepts)"
}
```

### Response to Client

```json
{
    "capture_id": "uuid",
    "action": "suggest",
    "suggestion_text": "Want me to solve that integral?",
    "suggestion_type": "solve",
    "confidence": "high",
    "follow_up_prompt": "Solve the integral ∫ sin(2x)dx from 0 to π step by step"
}
```

If action is "none", client does nothing — no notification, no UI change.

---

## Suggestion UI (Client-Side)

### Corner Notification

When backend returns a suggestion with medium/high confidence:

```
┌─────────────────────────────────────┐
│  ✦ Presto                     ✕    │
│  Want me to solve that integral?    │
│                                     │
│  [Yes, help me]     [Dismiss]       │
└─────────────────────────────────────┘
```

Position: Top-right corner, 16px from edges
Behavior:
- Slides in with subtle animation
- Auto-dismisses after 10 seconds if no interaction
- Max 1 notification visible at a time
- Minimum 60 seconds between notifications (anti-spam)
- If user dismisses 3 in a row, reduce frequency to every 2 minutes

"Yes, help me" action:
1. Sends `follow_up_prompt` to existing Presto answer pipeline
2. Opens the standard Presto overlay with the streamed response
3. Logs acceptance for session context

### Persistent Prompt Box

Always visible during Study Mode. Compact text field at bottom-right:

```
┌──────────────────────────────────────────┐
│  Ask Presto anything...          ⌘⏎  │
└──────────────────────────────────────────┘
```

- Draggable to any screen edge
- Expands on focus to show recent session context
- Submissions go through the EXISTING answer pipeline but with session context injected
- Session context added to system prompt: "The user has been working on {summary} for {duration}. They've visited {apps}. Recent clipboard: {text}"

### Prompt Box Expanded State (on focus)

```
┌──────────────────────────────────────────┐
│  Study Mode · 23 min                     │
│  Working on: ISE 340 Homework            │
│  ─────────────────────────────────────── │
│  Ask Presto anything...          ⌘⏎  │
└──────────────────────────────────────────┘
```

---

## Session Context & Memory

### What Gets Stored (PostgreSQL)

```sql
CREATE TABLE study_sessions (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    duration_seconds INT,
    captures_count INT DEFAULT 0,
    suggestions_shown INT DEFAULT 0,
    suggestions_accepted INT DEFAULT 0,
    questions_asked INT DEFAULT 0
);

CREATE TABLE study_captures (
    id UUID PRIMARY KEY,
    session_id UUID REFERENCES study_sessions(id),
    captured_at TIMESTAMPTZ NOT NULL,
    app_name TEXT,
    window_title TEXT,
    -- NO image stored, NO clipboard stored
    -- Only metadata for session context
    suggestion_action TEXT, -- 'suggest' | 'none'
    suggestion_type TEXT,
    suggestion_accepted BOOLEAN DEFAULT FALSE
);
```

Key privacy rule: **Images are NEVER stored server-side.** They're processed in the Claude API call and discarded. Only metadata (app name, window title, suggestion type) is logged for session context.

### Session Context Injection

When user asks a question via the prompt box, or when generating the next analysis prompt, inject accumulated session context:

```python
def build_session_context(session_id: str) -> str:
    captures = get_recent_captures(session_id, limit=10)
    apps = set(c.app_name for c in captures)
    windows = [c.window_title for c in captures[-5:]]
    
    return f"""
    Session duration: {session.duration_minutes} minutes
    Apps used: {', '.join(apps)}
    Recent windows: {'; '.join(windows)}
    Suggestions shown: {session.suggestions_shown}
    Suggestions accepted: {session.suggestions_accepted}
    """
```

---

## Privacy & Security Model

### Principles

1. **User-initiated only.** Study Mode requires explicit toggle. Never activates automatically.
2. **Local-first filtering.** Private apps filtered client-side before any screenshot is taken.
3. **No image persistence.** Screenshots exist in memory during API call only. Never written to disk, never stored on server.
4. **Metadata-only logging.** Server stores app names and window titles for session context. No screenshot data, no clipboard data persisted.
5. **Session-scoped.** All in-memory context cleared when Study Mode is toggled off.
6. **Transparent.** Menu bar always shows Study Mode state. Session stats visible at a glance.

### User Controls

- App exclusion list (Settings > Study Mode > Excluded Apps)
- Capture frequency slider (15s / 30s / 45s / 60s)
- Suggestion frequency limit (every 30s / 60s / 120s / manual only)
- "Pause" button in prompt box (temporarily stops capture without ending session)
- Session history in admin panel (metadata only: duration, apps, suggestion count)

### macOS Permissions

Study Mode requires Screen Recording permission (already granted for Cmd+Shift+X).
No additional permissions needed beyond what Presto AI already requests.

### First-Time Activation Flow

When user first toggles Study Mode:

```
┌─────────────────────────────────────────────┐
│                                             │
│  Study Mode                                 │
│                                             │
│  Presto will periodically analyze your      │
│  screen to suggest help while you work.     │
│                                             │
│  ✦ Screenshots are analyzed and immediately │
│    discarded — never saved                  │
│  ✦ Private apps (banking, messaging) are    │
│    automatically excluded                   │
│  ✦ You control capture frequency            │
│  ✦ Toggle off anytime with ⌘⇧S             │
│                                             │
│  [Customize Exclusions]  [Enable Study Mode]│
│                                             │
└─────────────────────────────────────────────┘
```

---

## Monetization

Study Mode is a **paid-only feature**. It's the primary upgrade driver.

- Free tier: Cmd+Shift+X only (15 shots/day on Sonnet)
- Paid tier ($5.99/month): Unlimited shots + Study Mode
- Study Mode consumes ~2x the API cost of manual shots (vision analysis is heavier), but drives dramatically higher retention

Consider a "Study Mode trial" — 3 free Study Mode sessions to demonstrate value before paywall.

---

## Implementation Phases

### Phase 1: Core Loop (ship first)
- Cmd+Shift+S toggle
- Silent screenshot capture on window change + 45s timer
- Backend `/study/analyze` endpoint with Claude vision
- Corner notification with accept/dismiss
- Basic prompt box (sends to existing pipeline with context)

### Phase 2: Smart Context
- Session context injection into analysis prompts
- Clipboard monitoring for richer context
- App exclusion list UI
- Capture/suggestion frequency controls
- Session stats in menu bar dropdown

### Phase 3: Stickiness Features  
- Session history and analytics
- Knowledge graph across sessions (what topics you've worked on)
- Auto-generated study summaries at session end
- Flashcard generation from accepted suggestions

---

## API Cost Estimation

Per Study Mode session (1 hour):
- Captures: ~40-80 (depending on activity + throttling)
- After filtering (low-confidence "none" responses): ~15-25 actual API calls with vision
- Cost per vision call (Haiku with image): ~$0.005-0.01
- Total per hour: ~$0.10-0.25
- Daily active user (2 hours/day): ~$0.20-0.50/day

At $5.99/month, you need users to average <$5 in API costs/month = ~10-25 hours of Study Mode. Achievable with smart throttling.

### Cost Optimization Levers
- Use Haiku for screen analysis (cheaper, fast enough for "what is this" classification)
- Use Sonnet only for actual answer generation when user accepts a suggestion
- Skip captures when screen hasn't meaningfully changed (perceptual hash comparison)
- Batch context: send window titles without screenshots for low-activity periods, only attach screenshot when something looks actionable

---

## Naming

"Study Mode" works for the student market. For broader positioning (email, coding, general productivity), consider:

- **Focus Mode** — broader, implies productivity
- **Copilot Mode** — familiar concept, but trademark risk
- **Assist Mode** — generic but clear
- **Watch Mode** — honest about what it does

Recommendation: Ship as "Study Mode" for UM launch. Rename to "Assist Mode" or "Focus Mode" when expanding beyond students.
