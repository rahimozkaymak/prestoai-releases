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
- `PrestoAI/Views/OverlayManager-3.swift` — add auto-solve result methods, add `aLbeta` button to study bar HTML
- `PrestoAI/PrestoAIApp.swift` — replace all `StudyModeManager.shared` + `AutoSolveManager.shared` calls with `StudyCoordinator.shared`
- `Presto backend/main.py` — fix 500 error, update `AutoSolveRequest` model, update solve system prompt

---

## Section 1: StudyCoordinator

Single `class StudyCoordinator` with `static let shared` singleton. No sub-objects; all logic in one file with clearly delimited `// MARK:` sections.

### State Properties

```swift
// Session
private(set) var isActive = false
private(set) var isPaused = false
private var session: StudySession?          // stats for backend reporting
private var sessionMemory: SessionMemory?   // questions + solved set

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

// Auto solve
private var solverTasks: [Task<Void, Never>] = []
private var solversInFlight = 0
```

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
}
```

`PrivacyFilter` stays as a private struct inside `StudyCoordinator.swift` (same logic as today).

### Public API

```swift
func startSession()
func endSession()
func pause()
func resume()
func toggleAutoSolve()
func handleUserAcceptedSuggestion(questionId: Int)
func recordQuestionAsked()
func buildSessionContextPrompt() -> String?
```

### Callbacks (out to PrestoAIApp)

```swift
var onNeedsOnboarding: (() -> Void)?
var onSessionEnded: ((String) -> Void)?       // summary string
var onSuggestionAccepted: ((String) -> Void)? // followUpPrompt
var onSuggestionDismiss: (() -> Void)?
```

---

## Section 2: Session Lifecycle

### `startSession()`
1. Guard paid state; call `onNeedsOnboarding?()` if first time (same onboarding gate as today)
2. Create `StudySession` + empty `SessionMemory`; set `isActive = true`
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
2. Compute page fingerprint from OCR text (reuse `frameSimilarity` pixel-sampling approach)
3. If page changed → re-POST `stage: "identify"` to refresh memory; reset solved set
4. Call `sessionMemory.nextUnsolvedQuestion()`
5. If `nil` → skip cycle (all solved or no questions)
6. Respect anti-spam: `consecutiveDismissals >= 3` → effective interval 120s
7. Show popup: `OverlayManager.showStudySuggestion("Want to solve Q\(id)? \(summary)")` — existing accept/dismiss mechanism
8. On accept → `handleUserAcceptedSuggestion(questionId:)`
9. On dismiss → `consecutiveDismissals += 1`

**`handleUserAcceptedSuggestion(questionId:)`:**
1. Get question from `sessionMemory`
2. POST `stage: "solve"` with question text + global context + hint
3. Display answer in study bar via `onSuggestionAccepted?(followUpPrompt)` callback
4. `sessionMemory.markSolved(id)`
5. Log: `[Coordinator] Q\(id) solved and marked in memory`

---

## Section 4: Auto Solve

### `toggleAutoSolve()`
- **ON:** `autoSolveActive = true`, stop suggestion timer, run `performAutoSolve()`; log `[Coordinator] Auto Solve ON — suggestions paused`
- **OFF:** `autoSolveActive = false`, cancel solver tasks, call `OverlayManager.clearAutoSolveResults()`, restart suggestion timer; log `[Coordinator] Auto Solve OFF — suggestions resumed`

### `performAutoSolve()`
1. Collect all unsolved questions from `sessionMemory`
2. If empty → show "All questions solved" in overlay, return
3. `solversInFlight = unsolved.count`
4. Launch one `Task` per question → `solveQuestion(id:questionText:globalContext:hint:)`
5. As each solver returns (on `MainActor`) → `OverlayManager.appendAutoSolveAnswer(id:latex:copyable:isMC:)`; `sessionMemory.markSolved(id)`
6. Log per question: `[AutoSolve] Re-solving Q\(id)` (re-solve) or `[AutoSolve] Solver Q\(id) completed`

### Re-solve
Re-solve button calls `solveQuestion` for that id; on return calls `OverlayManager.replaceAutoSolveAnswer(id:latex:copyable:isMC:)`.

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

### New OverlayManager Methods
```swift
func showAutoSolveResults(count: Int)
func appendAutoSolveAnswer(id: Int, latex: String, copyable: String, isMC: Bool)
func replaceAutoSolveAnswer(id: Int, latex: String, copyable: String, isMC: Bool)
func clearAutoSolveResults()
```
All inject HTML into the existing study bar WKWebView via `evaluateJavaScript`. MathJax already loaded in the overlay renders LaTeX immediately.

### Study Bar Button Changes
- **Auto Solve** (existing): text toggles `"Auto Solve"` ↔ `"Stop Solving"`; calls `StudyCoordinator.shared.toggleAutoSolve()`
- **aLbeta** (new): inserted between Auto Solve and Pause; greyed out, disabled, no-op on click; tooltip/label "Auto-Locate (Beta) — Coming Soon"
- **Pause / Stop**: unchanged

---

## Section 5: Backend (`main.py`)

### Fix 500 Error
Add `import traceback` if not present. In outer `except` of `auto_solve`:
```python
except Exception as e:
    logger.error(f"[AutoSolve] error: {e}", exc_info=True)
    print(traceback.format_exc())
    raise HTTPException(500, "Auto-solve failed")
```

### Fix `AutoSolveRequest` Model
Ensure `global_context` and `answer_box_hint` are explicit declared fields (missing fields on the Pydantic model is the likely cause of the 500):
```python
class AutoSolveRequest(BaseModel):
    stage: str
    image: str | None = None
    media_type: str = "image/jpeg"
    question_text: str | None = None
    global_context: str | None = None
    answer_box_hint: str | None = None
    session_id: str | None = None
    device_id: str | None = None
```

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

```swift
// Study Mode activation
StudyCoordinator.shared.startSession()

// Study Mode deactivation
StudyCoordinator.shared.endSession()

// Auto Solve button
StudyCoordinator.shared.toggleAutoSolve()

// Pause/Resume
StudyCoordinator.shared.pause()
StudyCoordinator.shared.resume()
```

All `StudyModeManager.shared` and `AutoSolveManager.shared` references in `PrestoAIApp.swift` are replaced with `StudyCoordinator.shared`. Callback wiring (`onNeedsOnboarding`, `onSessionEnded`, `onSuggestionAccepted`, `onSuggestionDismiss`) follows the same pattern as today.

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
