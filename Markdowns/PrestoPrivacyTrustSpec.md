# Presto AI — Privacy & Trust Spec

## Core Messaging Frame

**Tagline:** "Presto AI forgets."

**One-liner:** "Study Mode sees your screen, helps you, and forgets. No screenshots saved. Ever."

**Expanded (for landing page hero or about section):**
"Most AI tools store everything. Presto does the opposite. When Study Mode analyzes your screen, the screenshot exists in memory for exactly one API call — then it's gone. No disk writes. No server storage. No training data. We built Presto to help you in the moment and forget immediately after."

**Never say:**
- "We take your privacy seriously" (meaningless)
- "Bank-grade encryption" (nobody believes this)
- "Your data is safe with us" (vague, unverifiable)
- "256-bit encrypted" (sounds like a VPN ad)

**Always say:**
- Exactly what happens, in what order, with what technology
- What is NOT stored
- What the user can verify themselves

---

## Privacy Page (get-prestoai.com/privacy)

This is NOT a legal privacy policy. This is a technical transparency document. The legal policy can exist separately at /legal/privacy-policy. This page is marketing-as-engineering.

### Page Structure

**Section 1: "What happens when Study Mode captures your screen"**

A numbered, visual pipeline showing the exact data lifecycle:

1. CAPTURE — CGWindowListCreateImage grabs a screenshot of your active window. JPEG compressed to 1024px max dimension, quality 60%. Stored in RAM only. Never touches your disk.

2. FILTER — Before any network request, Presto checks the frontmost app against an exclusion list: banking apps, password managers, messaging apps, incognito/private windows. If matched, the capture is dropped immediately. You'll see "Capture skipped — private app detected" in the status bar.

3. TRANSMIT — The JPEG + context metadata (app name, window title, timestamp) is sent over TLS 1.3 to our backend on Railway. The request payload is not logged.

4. ANALYZE — Our backend sends the image to Claude API (Anthropic) in a single vision request. Claude processes the image and returns a structured suggestion. Anthropic does not store images submitted via API and does not use them for training.

5. DISCARD — The image payload is discarded on our server immediately after the Claude API response. No image data is written to any database, file system, or cache. The in-memory reference is released.

6. RESPOND — Only the suggestion text is returned to your device. The screenshot no longer exists anywhere.

**Persisted data (the only things we store):**
- Your user ID
- Session start/end timestamps
- Per-capture metadata: app name, window title, suggestion type (solve/draft/explain), whether you accepted or dismissed
- No screenshot data. No clipboard text. No window contents.

**Section 2: "What Presto never does"**

Bullet list, each starting with "Never":
- Never writes screenshots to disk (client or server)
- Never stores clipboard contents on our servers
- Never records audio or keystrokes
- Never sends data when Study Mode is off
- Never captures excluded apps (you control the list)
- Never sells, shares, or uses your data for model training
- Never runs in the background without the Study Mode indicator visible

**Section 3: "Verify it yourself"**

- Link to open-source capture pipeline on GitHub (StudyModeCapture.swift)
- Instructions to monitor network traffic with Proxyman or Charles Proxy
- Explanation of what the user will see: JPEG payload out, JSON suggestion back, no persistent connections
- "If you find something that contradicts what's on this page, email rahim@get-prestoai.com directly."

**Section 4: "Third-party services"**

Table format:
| Service | What it receives | Data retention | Training policy |
|---------|-----------------|----------------|-----------------|
| Anthropic (Claude API) | Screenshot image + text prompt | Not stored after processing | Not used for training (API ToS) |
| Railway (hosting) | Encrypted request in transit | No image logging | N/A |
| Polar (payments) | Email, payment method | Per their privacy policy | N/A |
| Cloudflare (CDN) | Standard web traffic | Standard CDN caching | N/A |

**Section 5: "Questions"**

Direct email link. Not a form. Not a chatbot. "Email rahim@get-prestoai.com and I'll answer personally."

---

## First-Launch Onboarding Flow (Study Mode)

Triggered the FIRST time user toggles Study Mode. Never shown again after completion (but accessible from Settings > Study Mode > Privacy Demo).

### Screen 1: "Study Mode sees what you see"

Simple illustration: Presto icon + screen outline + eye icon.

Copy: "When Study Mode is on, Presto periodically captures your screen to understand what you're working on and suggest help."

Button: "Show me how it works"

### Screen 2: Live Demo — Capture

Actually captures the user's current screen right now.

Shows the screenshot thumbnail in the overlay with a pulsing border.

Copy: "This is what Presto just captured. It's in memory — not saved anywhere."

Metadata shown below thumbnail:
- App: [detected app name]
- Window: [detected window title]
- Size: [X KB in memory]
- Disk writes: 0

Button: "Next — watch it analyze"

### Screen 3: Live Demo — Analyze

Shows a loading animation as the screenshot is sent to the backend.

Network indicator lights up green during transmission.

Copy: "Presto is sending this to Claude for analysis. Watch the network indicator — it'll go dark when the transfer is done."

After response arrives, show:
- Suggestion: [whatever Claude returned, e.g., "Want help with that code?"]
- Status: "Image discarded from server"
- Time alive: "Screenshot existed for 2.3 seconds"

Button: "Next — verify it's gone"

### Screen 4: Live Demo — Proof of Deletion

Show an empty data log:

```
Session data:
- captures: 1
- images stored: 0
- clipboard stored: 0
- disk writes: 0
```

Copy: "That's it. The screenshot is gone. All Presto remembers is that you were in [app name] and it suggested help. Nothing else."

Link: "Read our full technical privacy page" → get-prestoai.com/privacy

Button: "Enable Study Mode"

### Screen 5: Exclusion Setup

Show list of detected apps on the user's system with toggle switches.

Pre-toggled OFF (excluded by default):
- 1Password / Keychain Access
- Messages / Signal / WhatsApp / Telegram
- System Preferences
- Any detected banking apps

Copy: "These apps are excluded by default. Presto will never capture them. You can add more anytime in Settings."

Button: "Done — Start Study Mode"

---

## In-App Trust Indicators (Always Visible During Study Mode)

### Prompt Box Status Line

The persistent prompt box during Study Mode shows a single status line at the top:

Default state: "Study Mode · 0 images stored · 23 min"

During capture: "Analyzing screen..." (with network dot lit)

After capture: "Helped with [suggestion type] · image discarded" (fades back to default after 3s)

Private app detected: "Paused — [App Name] is excluded" (amber text)

Study Mode off: prompt box disappears entirely

### Network Activity Dot

Small dot (6px) in the corner of the prompt box:
- Gray: no network activity
- Green pulse: data transmitting to backend
- Off: Study Mode idle

This is subtle but critical — the user can glance at it anytime and know whether data is moving. When it's gray, nothing is happening. Period.

### Menu Bar Indicators

When Study Mode is active:
- Menu bar icon shows a subtle animated ring or different tint
- Dropdown shows: "Study Mode active · 14 captures · 0 stored · 31 min"
- "Pause" button (stops capture without ending session)
- "Stop Study Mode" button (ends session, clears all in-memory data)

### Session End Summary

When user stops Study Mode, show a brief dismissible notification:

"Session ended — 45 minutes
Analyzed 12 screens, suggested help 4 times.
0 screenshots saved. Session data cleared."

---

## Open Source Strategy

### What to open-source:

Only the capture pipeline. Specifically:
- StudyModeCapture.swift — the screenshot capture, compression, and memory management
- PrivacyFilter.swift — the app exclusion logic and window title filtering
- NetworkTransmit.swift — the HTTPS request that sends the image (shows exactly what's sent and that the image reference is released after)

### What stays closed:
- Backend analysis logic and prompt engineering
- Suggestion UI and cadence engine
- Subscription/auth system
- Everything else in the app

### Where to publish:
- GitHub repo: prestoai/study-mode-capture (or similar)
- Link from the privacy page and from the app's Settings > Study Mode > "Verify our code"
- README explains what the code does, how to audit it, and how to monitor network traffic

### Why this works:
- Security researchers can verify claims without you spending money on audits
- Users who care deeply about privacy (your highest-risk churn group) get concrete proof
- The rest of your users never look at it but feel better knowing it exists
- Competitors can see HOW you capture but not your analysis prompts or suggestion logic — the capture pipeline is commodity, the intelligence layer is the moat

---

## Copywriting Cheat Sheet

For landing page:
"Presto AI forgets. Every screenshot is analyzed and discarded in seconds. Nothing is saved. Ever."

For App Store description:
"Study Mode watches your screen and suggests help — then immediately forgets what it saw. No screenshots stored, no data sold, no exceptions."

For onboarding:
"Watch Presto capture, analyze, and delete. The whole cycle takes seconds. Then the screenshot is gone forever."

For comparison with competitors:
"Unlike tools that record your entire screen history, Presto processes and discards. We don't build a timeline of your activity. We help you in the moment and move on."

For skeptics:
"Don't trust us. Verify. Our capture pipeline is open source. Monitor our network traffic. Read the code. If anything contradicts what we say, email us."
