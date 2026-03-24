# Study Mode Coordinator + Auto Solve Rewrite — Design Spec

**Date:** 2026-03-24
**Status:** Approved

---

## Overview

Major rewrite that merges `StudyModeManager` and `AutoSolveManager` into a single `StudyCoordinator` — the central brain of Study Mode. Floating answer bubbles are replaced by inline answers rendered inside the existing Study Mode overlay. A new session memory system tracks identified questions and solved state across the session.

---

## Files Changed

### Deleted
- `PrestoAI/Services/AutoSolveManager.swift`
- `PrestoAI/Views/AnswerBubbleWindow.swift`
- `PrestoAI/Services/StudyModeManager.swift`

### Created
- `PrestoAI/Services/StudyCoordinator.swift` — merged brain (~550 lines, single flat class with MARK sections)

### Modified
- `PrestoAI/Services/APIService.swift` — add `isMultipleChoice: Bool` to `SolveResult`; parse `is_multiple_choice` from solve response JSON
- `PrestoAI/Views/OverlayManager-3.swift` — add auto-solve result methods + `#autosolve-panel` div to study bar HTML; add `aLbeta` button
- `PrestoAI/PrestoAIApp.swift` — replace all `StudyModeManager.shared` + `AutoSolveManager.shared` calls with `StudyCoordinator.shared`; remove `$currentSuggestion` Combine sink (coordinator calls OverlayManager directly); update `sessionDurationText` binding
- `Presto backend/main.py` — add traceback print to 500 handler; update solve system prompt; confirm `AutoSolveRequest` fields

---

## Section 1: StudyCoordinator

Single `class StudyCoordinator: ObservableObject` with `static let shared` singleton. No sub-objects; all logic in one file with clearly delimited `// MARK:` sections.

### Published State (consumed by PrestoAIApp)

```swift
@Published private(set) var isActive = false
@Published private(set) var isPaused = false
@Published private(set) var sessionDurationText: String = ""
```

`currentSuggestion` is **not** published. Instead, the coordinator calls `OverlayManager.showStudySuggestion()` directly when a suggestion is ready — eliminating the existing `$currentSuggestion.sink` Combine chain in `PrestoAIApp`. The existing `onSuggestionAccept` / `onSuggestionDismiss` callbacks on `OverlayManager` remain and are wired to `StudyCoordinator`'s accept/dismiss handlers.

### Private State Properties

```swift
// Session
private var session: StudySession?          // stats for backend reporting
private var sessionMemory: SessionMemory?   // questions + solved set

// Capture decision (inlined — no separate CaptureDecision struct)
private var lastCaptureTime: Date = .distantPast
private var lastWindowTitle: String = ""
private var lastAppName: String = ""
private var userIsActivelyTyping = false

// Modes
private var autoSolveActive = false
private var suggestionTimer: Timer?

// OS monitors (merged from StudyModeManager)
private var captureTimer: Timer?
private var durationTimer: Timer?
private var typingTimer: Timer?
private var keyEventMonitor: Any?
private var appObserver: NSObjectProtocol?
private var isRequestInFlight = false
private var lastNotificationTime: Date = .distantPast
private var consecutiveDismissals = 0
private var isPrivateAppDetected = false

// Auto solve
private var solverTasks: [Task<Void, Never>] = []
private var solversInFlight = 0
```

`CaptureDecision` is **not** a separate struct — its four fields (`lastCaptureTime`, `lastWindowTitle`, `lastAppName`, `userIsActivelyTyping`) and its `shouldCapture` logic are inlined directly as private state + a private method on `StudyCoordinator`. The logic itself is preserved identically: capture on window/app change, capture on timer if `> interval` has elapsed, suppress if `userIsActivelyTyping`.

### Supporting Types

```swift
struct SessionMemory {
    var globalContext: String = ""
    var questions: [IdentifiedQuestion] = []
    var solvedQuestions: Set<Int> = []
    var currentPageSignature: String = ""
    var lastScreenText: String = ""

    func nextUnsolvedQuestion() -> IdentifiedQuestion? {
        questions.first { !solvedQuestions.contains($0.id) }
    }
    mutating func markSolved(_ id: Int) { solvedQuestions.insert(id) }
}

struct StudySession {
    let id: String
    let startedAt: Date
    var capturesCount: Int = 0
    var suggestionsShown: Int = 0
    var suggestionsAccepted: Int = 0
    var questionsAsked: Int = 0
    var appsVisited: Set<String> = []
    var recentWindowTitles: [String] = []
    // Note: previousSuggestions is intentionally removed — the question memory
    // system (SessionMemory.solvedQuestions) supersedes it as the anti-redundancy signal.
}
```

`PrivacyFilter` stays as a private struct inside `StudyCoordinator.swift` (same logic as today).

### Public API

```swift
func startSession()                          // generates sessionId internally; handles onboarding gate
func activateAfterOnboarding()               // sets hasShownOnboarding = true, then calls startSession()
func endSession()
func pause()
func resume()
func toggleAutoSolve()
func resolveQuestion(id: Int)                // re-solve a single question; called by OverlayManager on autoSolveResolve message
func handleUserAcceptedSuggestion(questionId: Int)
func dismissCurrentSuggestion()             // increments consecutiveDismissals; wired to overlayManager.onSuggestionDismiss
func recordQuestionAsked()
func buildSessionContextPrompt() -> String?
```

**`activateAfterOnboarding()`** replaces the two `StudyModeManager.shared.activateAfterOnboarding()` callsites in `PrestoAIApp` (lines 350 and 356). It sets `UserDefaults "studyModeOnboardingShown" = true` then calls `startSession()`.

### Callbacks (out to PrestoAIApp)

```swift
var onNeedsOnboarding: (() -> Void)?
var onSessionEnded: ((String) -> Void)?       // summary string
var onSuggestionAccepted: ((String) -> Void)? // followUpPrompt → injectPromptAndSubmit
```

`onSuggestionDismiss` is handled internally (increments `consecutiveDismissals`); no external callback needed.

---

## Section 2: Session Lifecycle

### `startSession()`
1. Guard paid state; call `onNeedsOnboarding?()` if `!hasShownOnboarding`; return
2. Create `StudySession(id: UUID().uuidString, startedAt: Date())` + empty `SessionMemory`; set `isActive = true`
3. Start OS monitors: app-switch observer, typing detection key monitor, capture timer (45s default), duration timer (30s)
4. After 3s delay: capture screen → POST `stage: "identify"` → store `globalContext` + `questions` in `sessionMemory`, set `currentPageSignature`
5. If `!autoSolveActive`: start suggestion timer (20s repeating)
6. Log: `[Coordinator] Session started, N questions found, memory initialized`

### `endSession()`
1. Stop suggestion timer, capture timer, duration timer, all OS monitors
2. Cancel all in-flight solver tasks; `solversInFlight = 0`
3. Call `reportSessionEnd()` → POST `/api/v1/study/session` (same payload as today)
4. Clear `sessionMemory = nil`, `session = nil`, `isActive = false`, `isPaused = false`
5. Call `onSessionEnded?(summary)`
6. Log: `[Coordinator] Session ended, memory cleared`

---

## Section 3: Smart Suggestions

Runs only when `!autoSolveActive`. Timer fires every 20 seconds.

**Each cycle:**
1. Capture screen silently
2. Compute page fingerprint via pixel-sampling (`frameSimilarity` approach from `AutoSolveManager`)
3. If page changed → re-POST `stage: "identify"` to refresh memory; reset `solvedQuestions`
4. Call `sessionMemory.nextUnsolvedQuestion()`
5. If `nil` → skip cycle (all solved or no questions found)
6. Respect anti-spam: `consecutiveDismissals >= 3` → effective interval 120s; `Date().timeIntervalSince(lastNotificationTime) < effectiveInterval` → skip
7. Set `overlayManager.onSuggestionAccept = { [weak self] in self?.handleUserAcceptedSuggestion(questionId: id) }` — captures `id` for the pending question
8. Call `overlayManager.showStudySuggestion("Want to solve Q\(id)? \(summary)")` directly (no Combine publish)
9. When user accepts: `onSuggestionAccept` fires → `handleUserAcceptedSuggestion(questionId:)`. When user dismisses: `onSuggestionDismiss` fires → `dismissCurrentSuggestion()` → `consecutiveDismissals += 1`

**`handleUserAcceptedSuggestion(questionId:)`:**
1. Get question from `sessionMemory`
2. POST `stage: "solve"` with question text + global context + hint
3. Format as `followUpPrompt` string: `"Q\(id): \(questionText)\n\nAnswer: \(result.answerLatex)"`
4. Call `onSuggestionAccepted?(followUpPrompt)` → `PrestoAIApp` calls `overlayManager.injectPromptAndSubmit(followUpPrompt)` — same path as today
5. `sessionMemory.markSolved(id)`; `session?.suggestionsAccepted += 1`; `consecutiveDismissals = 0`
6. Log: `[Coordinator] Q\(id) solved and marked in memory`

---

## Section 4: Auto Solve

### `toggleAutoSolve()`
- **ON:** `autoSolveActive = true`, stop suggestion timer, run `performAutoSolve()`; log `[Coordinator] Auto Solve ON — suggestions paused`
- **OFF:** `autoSolveActive = false`, cancel solver tasks, call `overlayManager.clearAutoSolveResults()`, restart suggestion timer; log `[Coordinator] Auto Solve OFF — suggestions resumed`

### `performAutoSolve()`
1. Collect all questions from `sessionMemory` where `id ∉ solvedQuestions`
2. If empty → call `overlayManager.showAutoSolveResults(count: 0)` ("All questions solved"), return
3. Call `overlayManager.showAutoSolveResults(count: unsolved.count)` — renders container + header
4. `solversInFlight = unsolved.count`
5. Launch one `Task` per question → `solveQuestion(id:questionText:globalContext:hint:)`
6. As each solver returns (on `MainActor`): call `overlayManager.appendAutoSolveAnswer(id:latex:copyable:isMC:)`; `sessionMemory.markSolved(id)` ; `solversInFlight -= 1`
7. Log per question: `[AutoSolve] Solver Q\(id) completed`

### Re-solve
Re-solve button in HTML posts `{action: "autoSolveResolve", id: N}` via `window.webkit.messageHandlers.overlay`. `OverlayManager` receives this in the **existing single `userContentController(_:didReceive:)` switch block** (handler name `"overlay"`, same block that handles `"studyAutoSolve"`, `"studyStop"`, etc.) — add:

```swift
case "autoSolveResolve":
    if let id = dict["id"] as? Int {
        StudyCoordinator.shared.resolveQuestion(id: id)
    }
```

`resolveQuestion(id:)` on the coordinator calls `solveQuestion` for that id; on return calls `overlayManager.replaceAutoSolveAnswer(id:latex:copyable:isMC:)`. Log: `[AutoSolve] Re-solving Q\(id)`.

### `SolveResult` Update (APIService.swift)

```swift
struct SolveResult {
    let answerLatex: String
    let answerCopyable: String
    let isMultipleChoice: Bool    // ← new field; parsed from "is_multiple_choice" in JSON
}
```

In `APIService.solveQuestion`, after parsing the JSON dict:
```swift
let isMC = json["is_multiple_choice"] as? Bool ?? false
return SolveResult(answerLatex: latex, answerCopyable: copyable, isMultipleChoice: isMC)
```

### Answer Display Format

**Multiple choice:**
```
1A:  (e) 0.36°              [↻]
```
No copy button for MC.

**Non-MC:**
```
2A:  7.5 × 10⁻⁷ m    [📋] [↻]
```
Copy button copies `answer_copyable`. Re-solve button re-sends to solver.

### OverlayManager — Auto-Solve Panel

**HTML structure** added to the study bar template (inside the existing overlay, above the prompt input):

```html
<div id="autosolve-panel" style="display:none">
  <div class="autosolve-header" id="autosolve-header"></div>
  <div id="autosolve-rows"></div>
</div>
```

**New Swift methods on OverlayManager** (all call `evaluateJavaScript` on the study bar WKWebView):

```swift
func showAutoSolveResults(count: Int)
// JS: showAutosolvePanel(count)
// Sets header text; shows #autosolve-panel; clears #autosolve-rows

func appendAutoSolveAnswer(id: Int, latex: String, copyable: String, isMC: Bool)
// JS: appendAutosolveAnswer(id, escapedLatex, escapedCopyable, isMC)
// Appends a row to #autosolve-rows; MathJax.typesetPromise() called after append

func replaceAutoSolveAnswer(id: Int, latex: String, copyable: String, isMC: Bool)
// JS: replaceAutosolveAnswer(id, escapedLatex, escapedCopyable, isMC)
// Replaces the row with data-id="\(id)" in #autosolve-rows

func clearAutoSolveResults()
// JS: clearAutosolvePanel()
// Hides #autosolve-panel; clears #autosolve-rows
```

Each row has `data-id="\(id)"` for targeting by `replaceAutoSolveAnswer`. Row HTML:
```html
<div class="answer-row" data-id="N">
  <span class="q-num">NA:</span>
  <span class="answer">\(latex\)</span>
  <!-- copy button only for non-MC -->
  <button class="copy-btn" onclick="copyAutoAnswer(N, 'copyable')">📋</button>
  <button class="resolve-btn" onclick="resolveAnswer(N)">↻</button>
</div>
```

`resolveAnswer(N)` posts `{action: "autoSolveResolve", id: N}` via `window.webkit.messageHandlers.overlay`.
`copyAutoAnswer(N, text)` posts `{action: "copy", text: text}`.

MathJax is already loaded in the overlay; `MathJax.typesetPromise([row])` is called after each append/replace to render LaTeX.

### Study Bar Button Changes
- **Auto Solve** (existing): text toggles `"Auto Solve"` ↔ `"Stop Solving"`; calls `StudyCoordinator.shared.toggleAutoSolve()` via existing `studyAutoSolve` message action
- **aLbeta** (new): inserted between Auto Solve and Pause in the HTML; `disabled` attribute set; styled with `opacity: 0.4`; label "aLbeta"; `title="Auto-Locate (Beta) — Coming Soon"`; no JS action
- **Pause / Stop**: unchanged

---

## Section 5: Backend (`main.py`)

### Add Traceback Logging
Add `import traceback` at the top of `main.py` if not already imported. In the outer `except` of `auto_solve`:
```python
except Exception as e:
    logger.error(f"[AutoSolve] error: {e}", exc_info=True)
    print(traceback.format_exc())   # ← add this line
    raise HTTPException(500, "Auto-solve failed")
```

Note: `global_context` and `answer_box_hint` appear to already be declared on the `AutoSolveRequest` model. The real root cause of the 500 is unknown until the traceback is captured. Do not change the model fields unless the traceback reveals them as the issue.

### Update Solve System Prompt
Replace `AUTO_SOLVE_SOLVE_SYSTEM_TEMPLATE` with:

```
You are solving ONE homework/exam question.

Global context from the assignment:
{global_context}

Question:
{question_text}

The answer box expects: {answer_box_hint}

Return ONLY the final answer. No work, no explanation, no steps, no reasoning.

Rules:
- For multiple choice: return the letter AND the value.
  Example: {"answer_latex": "\\textbf{(e)} \\; 0.36^\\circ", "answer_copyable": "e", "is_multiple_choice": true}
- For non-multiple-choice: return just the answer value.
  Example: {"answer_latex": "7.5 \\times 10^{-7} \\text{ m}", "answer_copyable": "7.5e-7", "is_multiple_choice": false}
- answer_latex: LaTeX formatted. No equals sign prefix, no "Answer:" label.
- answer_copyable: Plain text for homework platforms (WebAssign, Pearson). Proper decimals, standard notation.
- is_multiple_choice: true if the question has lettered choices, false otherwise.

Respond with raw JSON only. No markdown, no code fences, no backticks.
```

---

## Section 6: Wiring in `PrestoAIApp`

### Setup (in `setupStudyModeCallbacks()`, replacing today's StudyModeManager wiring)

```swift
let coord = StudyCoordinator.shared

coord.onNeedsOnboarding = { [weak self] in
    self?.studyOnboardingController?.show(
        onEnable: {
            StudyCoordinator.shared.activateAfterOnboarding()
            self?.onStudyModeActivated()
        },
        onCustomize: {
            self?.openStudyModeSettings()
            StudyCoordinator.shared.activateAfterOnboarding()
            self?.onStudyModeActivated()
        }
    )
}

coord.onSuggestionAccepted = { [weak self] followUpPrompt in
    self?.overlayManager?.injectPromptAndSubmit(followUpPrompt)
}

coord.onSessionEnded = { [weak self] summary in
    self?.overlayManager?.dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self?.overlayManager?.showStudySummary(text: summary)
    }
    self?.refreshMenuState()
}

// Suggestion accept: coordinator sets this closure itself each time it calls
// overlayManager.showStudySuggestion() — capturing the pending questionId in a closure.
// PrestoAIApp must NOT set onSuggestionAccept; doing so would overwrite the coordinator's closure.
// Dismiss: PrestoAIApp wires this; the coordinator does not own it.
overlayManager?.onSuggestionDismiss = {
    StudyCoordinator.shared.dismissCurrentSuggestion()
}
```

### Toggle (replaces today's `toggleStudyMode`)

```swift
@objc private func toggleStudyMode() {
    if AppStateManager.shared.isOffline {
        overlayManager?.showError("Unable to connect to Presto AI servers. Check your internet connection and try again.")
        return
    }
    if StudyCoordinator.shared.isActive {
        StudyCoordinator.shared.endSession()
    } else {
        if AppStateManager.shared.currentState != .paid { showPaywall(); return }
        StudyCoordinator.shared.startSession()
        if StudyCoordinator.shared.isActive { onStudyModeActivated() }
    }
    refreshMenuState()
}
```

### `onStudyModeActivated()` overlay callbacks

```swift
overlayManager?.onAutoSolveToggle = { StudyCoordinator.shared.toggleAutoSolve() }
overlayManager?.onStudyPauseToggle = {
    StudyCoordinator.shared.isPaused
        ? StudyCoordinator.shared.resume()
        : StudyCoordinator.shared.pause()
}
overlayManager?.onStudyStop = { StudyCoordinator.shared.endSession() }
```

### Menu item refresh — `sessionDurationText`

Replace the existing `studyMode.$currentSuggestion` Combine sink with a sink on `StudyCoordinator.shared.$sessionDurationText` (or `$isActive`) to trigger `refreshMenuState()`. The menu item label uses `StudyCoordinator.shared.sessionDurationText` directly.

---

## Flow Summary

**Normal Study Mode (no auto-solve):**
```
startSession() → capture → identify → memory initialized
    ↓
Every 20s: suggestion popup → "Solve Q1?" → User clicks Yes
    ↓
solve Q1 → answer in overlay → Q1 marked solved in memory
    ↓
Next 20s: "Solve Q2?" (skips Q1)
```

**Auto Solve mode:**
```
toggleAutoSolve() ON → suggestions stop
    ↓
Solve ALL unsolved questions in parallel
    ↓
Answers appear in overlay list with copy + re-solve buttons
    ↓
toggleAutoSolve() OFF → suggestions resume with updated memory
```
