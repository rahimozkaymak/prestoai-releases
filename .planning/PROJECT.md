# Presto AI — Project Context

## What
macOS menu bar app: capture a screenshot region → AI analysis via Claude → floating overlay response. No dock icon, menu bar only.

## Stack
- **Client:** Swift/SwiftUI macOS app (Xcode project)
- **Backend:** Python FastAPI single-file (`Presto backend/main.py`, ~1060 lines), Railway-hosted
- **Website:** Static HTML/CSS/JS on Cloudflare Pages (`get-prestoai.com`)
- **AI:** Claude Haiku 4.5 via Anthropic API (SSE streaming)
- **Payments:** Polar (polar.sh)
- **Releases:** GitHub Releases on `rahimozkaymak/prestoai-releases` (DMG only)

## Current Version
v1.1 — initial source push. All core flows working: anonymous free tier (5 queries), paid subscriptions, referral system, promo codes, admin dashboard.

## Key Directories
- `/PrestoAI/` — Swift source (12 files)
- `/Presto backend/` — FastAPI backend (single main.py + requirements.txt)
- `/prestowebsite/` — Static website (4 HTML pages)
- `/PrestoAI.xcodeproj/` — Xcode project

## Development Goals (v1.2 Milestone)
Polish & stability first, then new features. Focus on shipping a reliable, professional product before scaling.
