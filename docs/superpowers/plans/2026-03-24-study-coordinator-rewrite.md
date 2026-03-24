# Study Coordinator Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `StudyModeManager` + `AutoSolveManager` + `AnswerBubbleWindow` with a single `StudyCoordinator` that owns session lifecycle, OS monitoring, smart suggestions, and auto-solve — rendering all answers inside the existing study bar overlay instead of floating bubbles.

**Architecture:** Single flat `ObservableObject` class (`StudyCoordinator`) with clearly delimited MARK sections. OverlayManager is extended with a `#autosolve-panel` div and 4 new Swift methods. PrestoAIApp is rewired to call `StudyCoordinator.shared` exclusively.

**Tech Stack:** Swift/SwiftUI, AppKit, WKWebView, Vision framework, Python/FastAPI (Railway backend)

**Spec:** `docs/superpowers/specs/2026-03-24-study-coordinator-rewrite-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Delete | `PrestoAI/Services/AutoSolveManager.swift` | Replaced by StudyCoordinator |
| Delete | `PrestoAI/Views/AnswerBubbleWindow.swift` | Replaced by inline overlay panel |
| Delete | `PrestoAI/Services/StudyModeManager.swift` | Replaced by StudyCoordinator |
| Create | `PrestoAI/Services/StudyCoordinator.swift` | Merged brain |
| Modify | `PrestoAI/Services/APIService.swift` | Add `isMultipleChoice` to `SolveResult` |
| Modify | `PrestoAI/Views/OverlayManager-3.swift` | Autosolve panel HTML/JS/Swift methods |
| Modify | `PrestoAI/Views/StudyModeViews.swift` | No code change needed — `PrivacyFilter` kept internal so line 174 still compiles |
| Modify | `PrestoAI/PrestoAIApp.swift` | Replace all old manager wiring |
| Modify | `Presto backend/main.py` | Traceback, system prompt, `is_multiple_choice` in response |

---

## Task 1: Backend — traceback + system prompt + is_multiple_choice

**Files:**
- Modify: `Presto backend/main.py`

- [ ] **Step 1: Add `traceback` to imports**

  Open `Presto backend/main.py`. Line 14 is `import logging`. Add after it:
  ```python
  import traceback
  ```

- [ ] **Step 2: Replace `AUTO_SOLVE_SOLVE_SYSTEM_TEMPLATE`**

  Find the block starting at `AUTO_SOLVE_SOLVE_SYSTEM_TEMPLATE = """` (~line 1395) and replace the entire string:
  ```python
  AUTO_SOLVE_SOLVE_SYSTEM_TEMPLATE = """You are solving ONE homework/exam question.

  Global context from the assignment:
  {global_context}

  Question:
  {question_text}

  The answer box expects: {answer_box_hint}

  Return ONLY the final answer. No work, no explanation, no steps, no reasoning.

  Rules:
  - For multiple choice: return the letter AND the value. Example: {{"answer_latex": "\\\\textbf{{(e)}}\\ \\; 0.36^\\\\circ", "answer_copyable": "e", "is_multiple_choice": true}}
  - For non-multiple-choice: return just the answer value. Example: {{"answer_latex": "7.5 \\\\times 10^{{-7}} \\\\text{{ m}}", "answer_copyable": "7.5e-7", "is_multiple_choice": false}}
  - answer_latex: LaTeX formatted. No equals sign prefix, no "Answer:" label.
  - answer_copyable: Plain text for homework platforms (WebAssign, Pearson). Proper decimals, standard notation.
  - is_multiple_choice: true if the question has lettered choices, false otherwise.

  Respond with raw JSON only. No markdown, no code fences, no backticks."""
  ```

- [ ] **Step 3: Update the `.format()` call and user message**

  Find (~line 1463):
  ```python
  system_prompt = AUTO_SOLVE_SOLVE_SYSTEM_TEMPLATE.format(
      global_context=req.global_context or "None provided",
      answer_box_hint=req.answer_box_hint or "any appropriate format",
  )
  text_content, inp_tok, out_tok, _ = await call_ai_text(
      system_prompt, f"Question:\n{req.question_text}", model, 1024
  )
  ```
  Replace with:
  ```python
  system_prompt = AUTO_SOLVE_SOLVE_SYSTEM_TEMPLATE.format(
      global_context=req.global_context or "None provided",
      question_text=req.question_text,
      answer_box_hint=req.answer_box_hint or "any appropriate format",
  )
  text_content, inp_tok, out_tok, _ = await call_ai_text(
      system_prompt, "Solve it.", model, 1024
  )
  ```

- [ ] **Step 4: Add `is_multiple_choice` to the solve return**

  Find (~line 1506):
  ```python
  else:
      return {
          "answer_latex": parsed.get("answer_latex", ""),
          "answer_copyable": parsed.get("answer_copyable", ""),
      }
  ```
  Replace with:
  ```python
  else:
      return {
          "answer_latex": parsed.get("answer_latex", ""),
          "answer_copyable": parsed.get("answer_copyable", ""),
          "is_multiple_choice": parsed.get("is_multiple_choice", False),
      }
  ```

- [ ] **Step 5: Add traceback print to the outer except**

  Find (~line 1514):
  ```python
  except Exception as e:
      logger.error(f"[AutoSolve] error: {e}", exc_info=True)
      raise HTTPException(500, "Auto-solve failed")
  ```
  Replace with:
  ```python
  except Exception as e:
      logger.error(f"[AutoSolve] error: {e}", exc_info=True)
      print(traceback.format_exc())
      raise HTTPException(500, "Auto-solve failed")
  ```

- [ ] **Step 6: Commit and push to prestoai-backend**

  ```bash
  cd "/Volumes/T7/PrestoAI/Presto backend"
  git add main.py
  git commit -m "fix: add traceback logging, update solve prompt with question_text and is_multiple_choice"
  git push origin main
  ```
  Expected: Railway auto-deploys.

---

## Task 2: APIService — add `isMultipleChoice` to `SolveResult`

**Files:**
- Modify: `PrestoAI/Services/APIService.swift:512-568`

- [ ] **Step 1: Add `isMultipleChoice` to `SolveResult`**

  Find:
  ```swift
  struct SolveResult {
      let answerLatex: String
      let answerCopyable: String
  }
  ```
  Replace with:
  ```swift
  struct SolveResult {
      let answerLatex: String
      let answerCopyable: String
      let isMultipleChoice: Bool
  }
  ```

- [ ] **Step 2: Parse `is_multiple_choice` in `solveQuestion`**

  Find:
  ```swift
  return SolveResult(
      answerLatex: json["answer_latex"] as? String ?? "",
      answerCopyable: json["answer_copyable"] as? String ?? ""
  )
  ```
  Replace with:
  ```swift
  return SolveResult(
      answerLatex: json["answer_latex"] as? String ?? "",
      answerCopyable: json["answer_copyable"] as? String ?? "",
      isMultipleChoice: json["is_multiple_choice"] as? Bool ?? false
  )
  ```

- [ ] **Step 3: Build to verify no compile errors in APIService**

  Product → Build (⌘B). Errors in `PrestoAIApp.swift` from deleted types are expected and resolved in later tasks.

---

## Task 3: Delete old files + create StudyCoordinator scaffold

**Files:**
- Delete: `PrestoAI/Services/AutoSolveManager.swift`
- Delete: `PrestoAI/Views/AnswerBubbleWindow.swift`
- Delete: `PrestoAI/Services/StudyModeManager.swift`
- Create: `PrestoAI/Services/StudyCoordinator.swift`

- [ ] **Step 1: Delete the three old files**

  ```bash
  rm /Volumes/T7/PrestoAI/PrestoAI/Services/AutoSolveManager.swift
  rm /Volumes/T7/PrestoAI/PrestoAI/Views/AnswerBubbleWindow.swift
  rm /Volumes/T7/PrestoAI/PrestoAI/Services/StudyModeManager.swift
  ```
  Then in Xcode project navigator: right-click each missing file → Delete Reference (the files are already gone from disk).

- [ ] **Step 2: Create `StudyCoordinator.swift` — add to Xcode project**

  Create `PrestoAI/Services/StudyCoordinator.swift`. In Xcode: File → Add Files to "PrestoAI" → select it → ensure PrestoAI target is checked.

- [ ] **Step 3: Write the scaffold (supporting types + state only — no method bodies)**

  Complete content of `StudyCoordinator.swift`:

  ```swift
  import AppKit
  import Vision
  import Combine
  import CoreGraphics

  // MARK: - SessionMemory

  struct SessionMemory {
      var globalContext: String = ""
      var questions: [APIService.IdentifiedQuestion] = []
      var solvedQuestions: Set<Int> = []
      var lastCGImage: CGImage?   // for page-change detection

      func nextUnsolvedQuestion() -> APIService.IdentifiedQuestion? {
          questions.first { !solvedQuestions.contains($0.id) }
      }
      mutating func markSolved(_ id: Int) { solvedQuestions.insert(id) }
  }

  // MARK: - StudySession

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

  // MARK: - PrivacyFilter
  // NOTE: NOT private — StudyModeViews.swift line 174 references PrivacyFilter.defaultExcludedApps directly.
  // Keep as internal (no access modifier) so it remains visible across the module.

  struct PrivacyFilter {
      static let defaultExcludedApps: Set<String> = [
          "1Password", "Keychain Access", "System Preferences", "System Settings",
          "Messages", "Signal", "WhatsApp", "Telegram",
          "LastPass", "Bitwarden", "Dashlane"
      ]
      static let excludedWindowTitleKeywords: [String] = [
          "Private Browsing", "Incognito", "password", "login", "sign in", "bank",
          "Password", "Login", "Sign In", "Bank"
      ]
      static func isExcluded(appName: String, windowTitle: String, userExclusions: Set<String>) -> Bool {
          let all = defaultExcludedApps.union(userExclusions)
          if all.contains(appName) { return true }
          let lower = windowTitle.lowercased()
          return excludedWindowTitleKeywords.contains { lower.contains($0.lowercased()) }
      }
  }

  // MARK: - StudyCoordinator

  class StudyCoordinator: ObservableObject {
      static let shared = StudyCoordinator()

      // MARK: Published State
      @Published private(set) var isActive = false
      @Published private(set) var isPaused = false
      @Published private(set) var sessionDurationText: String = ""

      // MARK: Callbacks
      var onNeedsOnboarding: (() -> Void)?
      var onSessionEnded: ((String) -> Void)?       // fired by endSession()
      var onSuggestionAccepted: ((String) -> Void)? // fired by handleUserAcceptedSuggestion; wired to injectPromptAndSubmit in PrestoAIApp

      // MARK: OverlayManager reference (set by PrestoAIApp)
      weak var overlayManager: OverlayManager?

      // MARK: Session
      private var session: StudySession?
      private var sessionMemory: SessionMemory?

      // MARK: Capture Decision (inlined)
      private var lastCaptureTime: Date = .distantPast
      private var lastWindowTitle: String = ""
      private var lastAppName: String = ""
      private var userIsActivelyTyping = false

      // MARK: Modes
      private var autoSolveActive = false
      private var suggestionTimer: Timer?

      // MARK: OS Monitors
      private var captureTimer: Timer?
      private var durationTimer: Timer?
      private var typingTimer: Timer?
      private var keyEventMonitor: Any?
      private var appObserver: NSObjectProtocol?
      private var isIdentifyInFlight = false
      private var lastNotificationTime: Date = .distantPast
      private var consecutiveDismissals = 0
      private var isPrivateAppDetected = false

      // MARK: Auto Solve
      private var solverTasks: [Task<Void, Never>] = []
      private var solversInFlight = 0

      // MARK: Onboarding
      private var hasShownOnboarding: Bool {
          get { UserDefaults.standard.bool(forKey: "studyModeOnboardingShown") }
          set { UserDefaults.standard.set(newValue, forKey: "studyModeOnboardingShown") }
      }

      // MARK: Settings
      var captureInterval: TimeInterval {
          let v = UserDefaults.standard.double(forKey: "studyModeCaptureInterval")
          return v > 0 ? v : 45
      }
      var userExcludedApps: Set<String> {
          Set(UserDefaults.standard.stringArray(forKey: "studyModeExcludedApps") ?? [])
      }

      private init() {}
  }
  ```

- [ ] **Step 4: Build — expect errors in PrestoAIApp from deleted types (that's fine)**

  Product → Build. New errors should only be in `PrestoAIApp.swift`.

- [ ] **Step 5: Commit scaffold**

  ```bash
  cd /Volumes/T7/PrestoAI
  git add PrestoAI/Services/StudyCoordinator.swift
  git add PrestoAI/PrestoAI.xcodeproj/project.pbxproj
  git commit -m "feat: scaffold StudyCoordinator, delete AutoSolveManager + AnswerBubbleWindow + StudyModeManager"
  ```

---

## Task 4: StudyCoordinator — Session Lifecycle + OS Monitors

**Files:**
- Modify: `PrestoAI/Services/StudyCoordinator.swift`

Add all method bodies inside the `StudyCoordinator` class body (after `private init() {}`).

- [ ] **Step 1: Add Public API — session control**

  ```swift
  // MARK: - Public API

  func startSession() {
      guard AppStateManager.shared.currentState == .paid else { return }
      guard !isActive else { return }
      if !hasShownOnboarding { onNeedsOnboarding?(); return }
      let newSession = StudySession(id: UUID().uuidString, startedAt: Date())
      session = newSession
      sessionMemory = SessionMemory()
      isActive = true; isPaused = false; consecutiveDismissals = 0
      startOSMonitors(); startCaptureTimer(); startDurationTimer()
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
          self?.performInitialIdentify()
      }
      print("[Coordinator] Session started — \(newSession.id)")
  }

  func activateAfterOnboarding() {
      hasShownOnboarding = true
      startSession()
  }

  func endSession() {
      guard isActive else { return }
      let summary = buildSessionSummary()
      suggestionTimer?.invalidate(); suggestionTimer = nil
      captureTimer?.invalidate(); captureTimer = nil
      durationTimer?.invalidate(); durationTimer = nil
      typingTimer?.invalidate(); typingTimer = nil
      if let m = keyEventMonitor { NSEvent.removeMonitor(m); keyEventMonitor = nil }
      if let o = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(o); appObserver = nil }
      for t in solverTasks { t.cancel() }
      solverTasks.removeAll(); solversInFlight = 0; autoSolveActive = false
      if let s = session { reportSessionEnd(s) }
      session = nil; sessionMemory = nil
      isActive = false; isPaused = false
      isIdentifyInFlight = false; sessionDurationText = ""
      consecutiveDismissals = 0; isPrivateAppDetected = false
      onSessionEnded?(summary)
      print("[Coordinator] Session ended, memory cleared")
  }

  func pause() {
      isPaused = true
      captureTimer?.invalidate(); captureTimer = nil
      print("[Coordinator] Paused")
  }

  func resume() {
      isPaused = false
      startCaptureTimer()
      print("[Coordinator] Resumed")
  }

  func recordQuestionAsked() { session?.questionsAsked += 1 }

  func buildSessionContextPrompt() -> String? {
      guard let s = session else { return nil }
      let mins = Int(Date().timeIntervalSince(s.startedAt) / 60)
      let apps = s.appsVisited.joined(separator: ", ")
      let windows = s.recentWindowTitles.suffix(5).joined(separator: "; ")
      return "Study Mode active \(mins) min. Apps: \(apps). Recent windows: \(windows)."
  }
  ```

- [ ] **Step 2: Add OS Monitors**

  ```swift
  // MARK: - OS Monitors

  private func startOSMonitors() {
      appObserver = NSWorkspace.shared.notificationCenter.addObserver(
          forName: NSWorkspace.didActivateApplicationNotification,
          object: nil, queue: .main
      ) { [weak self] note in
          guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
          self?.handleAppSwitch(appName: app.localizedName ?? "Unknown")
      }
      keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
          self?.userIsActivelyTyping = true
          self?.typingTimer?.invalidate()
          self?.typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
              self?.userIsActivelyTyping = false
          }
      }
  }

  private func startCaptureTimer() {
      captureTimer?.invalidate()
      captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
          self?.tickCaptureTimer()
      }
  }

  private func startDurationTimer() {
      durationTimer?.invalidate()
      durationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
          self?.updateDurationText()
      }
      updateDurationText()
  }

  private func startSuggestionTimer() {
      suggestionTimer?.invalidate()
      suggestionTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
          self?.tickSuggestionTimer()
      }
  }

  private func handleAppSwitch(appName: String) {
      guard isActive, !isPaused else { return }
      session?.appsVisited.insert(appName)
      let title = getCurrentWindowTitle()
      if PrivacyFilter.isExcluded(appName: appName, windowTitle: title, userExclusions: userExcludedApps) {
          isPrivateAppDetected = true; return
      }
      isPrivateAppDetected = false
  }

  private func tickCaptureTimer() {
      guard isActive, !isPaused, !isPrivateAppDetected else { return }
      let app = getCurrentAppName(); let title = getCurrentWindowTitle()
      if PrivacyFilter.isExcluded(appName: app, windowTitle: title, userExclusions: userExcludedApps) {
          isPrivateAppDetected = true; return
      }
      isPrivateAppDetected = false
      let windowChanged = title != lastWindowTitle || app != lastAppName
      let timeElapsed = Date().timeIntervalSince(lastCaptureTime) > captureInterval
      guard (windowChanged || timeElapsed) && !userIsActivelyTyping else { return }
      lastCaptureTime = Date(); lastWindowTitle = title; lastAppName = app
      session?.capturesCount += 1; session?.appsVisited.insert(app)
      if (session?.recentWindowTitles.count ?? 0) > 10 { session?.recentWindowTitles.removeFirst() }
      session?.recentWindowTitles.append(title)
  }

  private func updateDurationText() {
      guard let s = session else { return }
      let mins = Int(Date().timeIntervalSince(s.startedAt) / 60)
      if mins < 1 { sessionDurationText = "Just started" }
      else if mins < 60 { sessionDurationText = "\(mins) min" }
      else { sessionDurationText = "\(mins / 60)h \(mins % 60)m" }
  }
  ```

- [ ] **Step 3: Add Screen Capture + Helpers**

  ```swift
  // MARK: - Screen Capture + Helpers

  private func captureScreen() async -> (CGImage, String)? {
      guard CGPreflightScreenCaptureAccess() else {
          print("[Coordinator] No screen recording permission"); return nil
      }
      return await withCheckedContinuation { continuation in
          DispatchQueue.global(qos: .utility).async {
              guard let cg = CGWindowListCreateImage(
                  CGRect.null, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]
              ) else { continuation.resume(returning: nil); return }
              let bmp = NSBitmapImageRep(cgImage: cg)
              guard let png = bmp.representation(using: .png, properties: [:]) else {
                  continuation.resume(returning: nil); return
              }
              continuation.resume(returning: (cg, png.base64EncodedString()))
          }
      }
  }

  private func frameSimilarity(_ a: CGImage, _ b: CGImage) -> Double {
      guard a.width == b.width, a.height == b.height,
            let dA = a.dataProvider?.data as Data?,
            let dB = b.dataProvider?.data as Data? else { return 0.0 }
      let bprA = a.bytesPerRow, bppA = a.bitsPerPixel / 8
      let bprB = b.bytesPerRow, bppB = b.bitsPerPixel / 8
      let grid = 14, tol = 10; var matches = 0
      for row in 0..<grid {
          let y = row * a.height / grid
          for col in 0..<grid {
              let x = col * a.width / grid
              let oA = y * bprA + x * bppA, oB = y * bprB + x * bppB
              guard oA + 2 < dA.count, oB + 2 < dB.count else { continue }
              if abs(Int(dA[oA]) - Int(dB[oB])) <= tol &&
                 abs(Int(dA[oA+1]) - Int(dB[oB+1])) <= tol &&
                 abs(Int(dA[oA+2]) - Int(dB[oB+2])) <= tol { matches += 1 }
          }
      }
      return Double(matches) / Double(grid * grid)
  }

  private func getCurrentAppName() -> String {
      NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
  }

  private func getCurrentWindowTitle() -> String {
      guard let list = CGWindowListCopyWindowInfo(
          [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
      ) as? [[String: Any]],
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return "" }
      return list.first(where: {
          ($0[kCGWindowOwnerPID as String] as? Int32) == pid &&
          ($0[kCGWindowLayer as String] as? Int) == 0
      }).flatMap { $0[kCGWindowName as String] as? String } ?? ""
  }

  private func buildSessionSummary() -> String {
      guard let s = session else { return "" }
      let mins = Int(Date().timeIntervalSince(s.startedAt) / 60)
      let tasks = s.suggestionsAccepted
      return "\(mins)min session, helped with \(tasks) task\(tasks == 1 ? "" : "s")"
  }

  private func reportSessionEnd(_ s: StudySession) {
      let body: [String: Any] = [
          "session_id": s.id,
          "device_id": AppStateManager.shared.deviceID,
          "duration_seconds": Int(Date().timeIntervalSince(s.startedAt)),
          "captures_count": s.capturesCount,
          "suggestions_shown": s.suggestionsShown,
          "suggestions_accepted": s.suggestionsAccepted,
          "questions_asked": s.questionsAsked
      ]
      Task { try? await APIService.shared.reportStudySession(body: body) }
  }
  ```

- [ ] **Step 4: Add Initial Identify**

  ```swift
  // MARK: - Identify

  private func performInitialIdentify() {
      guard isActive else { return }
      Task { [weak self] in
          guard let self = self else { return }
          guard let (cgImage, base64) = await self.captureScreen() else { return }
          guard self.isActive else { return }
          let (compressed, _, _) = ImageCompressor.compressForStudy(base64)
          do {
              let result = try await APIService.shared.identifyQuestions(
                  image: compressed,
                  sessionId: self.session?.id ?? "",
                  deviceId: AppStateManager.shared.deviceID)
              guard self.isActive else { return }
              self.sessionMemory?.questions = result.questions
              self.sessionMemory?.globalContext = result.globalContext
              self.sessionMemory?.lastCGImage = cgImage
              print("[Coordinator] Session started, \(result.questions.count) questions found, memory initialized")
              if !self.autoSolveActive { self.startSuggestionTimer() }
          } catch {
              print("[Coordinator] Initial identify failed: \(error)")
          }
      }
  }
  ```

- [ ] **Step 5: Build — StudyCoordinator should compile cleanly**

  Product → Build. Errors only expected in `PrestoAIApp.swift`.

- [ ] **Step 6: Commit**

  ```bash
  cd /Volumes/T7/PrestoAI
  git add PrestoAI/Services/StudyCoordinator.swift
  git commit -m "feat: StudyCoordinator session lifecycle, OS monitors, capture helpers"
  ```

---

## Task 5: StudyCoordinator — Smart Suggestions

**Files:**
- Modify: `PrestoAI/Services/StudyCoordinator.swift`

- [ ] **Step 1: Add suggestion cycle inside the class**

  ```swift
  // MARK: - Smart Suggestions

  private func tickSuggestionTimer() {
      guard isActive, !isPaused, !autoSolveActive, !isPrivateAppDetected else { return }
      Task { [weak self] in await self?.runSuggestionCycle() }
  }

  private func runSuggestionCycle() async {
      guard isActive, !isIdentifyInFlight else { return }
      guard let (cgImage, base64) = await captureScreen() else { return }
      guard isActive else { return }

      // Page change detection
      if let prev = sessionMemory?.lastCGImage, frameSimilarity(prev, cgImage) < 0.85 {
          print("[Coordinator] Page changed — re-identifying")
          sessionMemory?.lastCGImage = cgImage
          sessionMemory?.solvedQuestions = []
          isIdentifyInFlight = true
          defer { isIdentifyInFlight = false }
          let (compressed, _, _) = ImageCompressor.compressForStudy(base64)
          do {
              let result = try await APIService.shared.identifyQuestions(
                  image: compressed,
                  sessionId: session?.id ?? "",
                  deviceId: AppStateManager.shared.deviceID)
              sessionMemory?.questions = result.questions
              sessionMemory?.globalContext = result.globalContext
              print("[Coordinator] Re-identified: \(result.questions.count) questions")
          } catch { print("[Coordinator] Re-identify failed: \(error)") }
      } else {
          sessionMemory?.lastCGImage = cgImage
      }

      guard isActive, !autoSolveActive else { return }
      guard let q = sessionMemory?.nextUnsolvedQuestion() else { return }

      let effectiveInterval = consecutiveDismissals >= 3 ? 120.0 : 20.0
      guard Date().timeIntervalSince(lastNotificationTime) >= effectiveInterval else { return }

      lastNotificationTime = Date()
      session?.suggestionsShown += 1
      let summary = String(q.questionText.prefix(60))
      let suggestionText = "Want to solve Q\(q.id)? \(summary)"

      await MainActor.run { [weak self] in
          guard let self = self else { return }
          self.overlayManager?.onSuggestionAccept = { [weak self] in
              self?.handleUserAcceptedSuggestion(questionId: q.id)
          }
          self.overlayManager?.showStudySuggestion(text: suggestionText)
      }
      print("[Coordinator] Suggestion shown for Q\(q.id)")
  }

  func handleUserAcceptedSuggestion(questionId: Int) {
      guard let q = sessionMemory?.questions.first(where: { $0.id == questionId }),
            let globalCtx = sessionMemory?.globalContext else { return }
      session?.suggestionsAccepted += 1
      consecutiveDismissals = 0
      Task { [weak self] in
          guard let self = self else { return }
          do {
              let result = try await APIService.shared.solveQuestion(
                  questionText: q.questionText,
                  globalContext: globalCtx,
                  answerBoxHint: q.answerBoxHint,
                  sessionId: self.session?.id ?? "",
                  deviceId: AppStateManager.shared.deviceID)
              self.sessionMemory?.markSolved(questionId)
              let display = "**Q\(questionId):** \(q.questionText)\n\n**Answer:** \(result.answerLatex)"
              await MainActor.run {
                  self.onSuggestionAccepted?(display)
              }
              print("[Coordinator] Q\(questionId) solved and marked in memory")
          } catch { print("[Coordinator] Solve Q\(questionId) failed: \(error)") }
      }
  }

  func dismissCurrentSuggestion() {
      consecutiveDismissals += 1
      print("[Coordinator] Suggestion dismissed (\(consecutiveDismissals) consecutive)")
  }
  ```

- [ ] **Step 2: Build**

  Product → Build.

- [ ] **Step 3: Commit**

  ```bash
  cd /Volumes/T7/PrestoAI
  git add PrestoAI/Services/StudyCoordinator.swift
  git commit -m "feat: StudyCoordinator smart suggestion cycle"
  ```

---

## Task 6: StudyCoordinator — Auto Solve

**Files:**
- Modify: `PrestoAI/Services/StudyCoordinator.swift`

- [ ] **Step 1: Add auto-solve methods inside the class**

  ```swift
  // MARK: - Auto Solve

  func toggleAutoSolve() {
      if autoSolveActive {
          autoSolveActive = false
          for t in solverTasks { t.cancel() }
          solverTasks.removeAll(); solversInFlight = 0
          overlayManager?.clearAutoSolveResults()
          startSuggestionTimer()
          print("[Coordinator] Auto Solve OFF — suggestions resumed")
      } else {
          autoSolveActive = true
          suggestionTimer?.invalidate(); suggestionTimer = nil
          performAutoSolve()
          print("[Coordinator] Auto Solve ON — suggestions paused")
      }
  }

  private func performAutoSolve() {
      guard let mem = sessionMemory else { return }
      let unsolved = mem.questions.filter { !mem.solvedQuestions.contains($0.id) }
      guard !unsolved.isEmpty else {
          overlayManager?.showAutoSolveResults(count: 0)
          return
      }
      overlayManager?.showAutoSolveResults(count: unsolved.count)
      solversInFlight = unsolved.count
      for q in unsolved {
          let t = Task { [weak self] in
              guard let self = self else { return }
              await self.runSolver(q: q)
          }
          solverTasks.append(t)
      }
  }

  private func runSolver(q: APIService.IdentifiedQuestion) async {
      defer {
          solversInFlight = max(0, solversInFlight - 1)
          if solversInFlight == 0 { solverTasks.removeAll() }
      }
      guard autoSolveActive, let globalCtx = sessionMemory?.globalContext else { return }
      do {
          let result = try await APIService.shared.solveQuestion(
              questionText: q.questionText,
              globalContext: globalCtx,
              answerBoxHint: q.answerBoxHint,
              sessionId: session?.id ?? "",
              deviceId: AppStateManager.shared.deviceID)
          guard autoSolveActive else { return }
          sessionMemory?.markSolved(q.id)
          await MainActor.run { [weak self] in
              self?.overlayManager?.appendAutoSolveAnswer(
                  id: q.id, latex: result.answerLatex,
                  copyable: result.answerCopyable, isMC: result.isMultipleChoice)
          }
          print("[AutoSolve] Solver Q\(q.id) completed")
      } catch { print("[AutoSolve] Solver Q\(q.id) FAILED: \(error)") }
  }

  func resolveQuestion(id: Int) {
      guard let q = sessionMemory?.questions.first(where: { $0.id == id }),
            let globalCtx = sessionMemory?.globalContext else { return }
      print("[AutoSolve] Re-solving Q\(id)")
      let t = Task { [weak self] in
          guard let self = self else { return }
          do {
              let result = try await APIService.shared.solveQuestion(
                  questionText: q.questionText,
                  globalContext: globalCtx,
                  answerBoxHint: q.answerBoxHint,
                  sessionId: self.session?.id ?? "",
                  deviceId: AppStateManager.shared.deviceID)
              await MainActor.run { [weak self] in
                  self?.overlayManager?.replaceAutoSolveAnswer(
                      id: id, latex: result.answerLatex,
                      copyable: result.answerCopyable, isMC: result.isMultipleChoice)
              }
          } catch { print("[AutoSolve] Re-solve Q\(id) FAILED: \(error)") }
      }
      solverTasks.append(t)
  }
  ```

- [ ] **Step 2: Build — errors only in PrestoAIApp**

  Product → Build.

- [ ] **Step 3: Commit**

  ```bash
  cd /Volumes/T7/PrestoAI
  git add PrestoAI/Services/StudyCoordinator.swift
  git commit -m "feat: StudyCoordinator auto solve toggle, parallel solvers, resolveQuestion"
  ```

---

## Task 7: OverlayManager — HTML/CSS/JS additions

**Files:**
- Modify: `PrestoAI/Views/OverlayManager-3.swift`

- [ ] **Step 1: Add autosolve CSS**

  In `studyModeBarHTML()`, find the `extraStyle:` block. Append these styles at the end of the CSS string, immediately before the closing `"""))`:

  ```css
  /* Auto Solve panel */
  #autosolve-panel { display: none; padding: 8px 16px 4px; }
  .autosolve-header { font-size: 11px; font-weight: 600; color: var(--text-dim); margin-bottom: 6px; letter-spacing: 0.02em; }
  .answer-row { display: flex; align-items: baseline; gap: 6px; padding: 3px 0; font-size: 13px; color: var(--text); border-bottom: 1px solid var(--subtle-bg); }
  .answer-row:last-child { border-bottom: none; }
  .q-num { font-size: 11px; color: var(--text-dim); min-width: 28px; flex-shrink: 0; }
  .answer { flex: 1; }
  .as-copy-btn, .as-resolve-btn { background: none; border: none; cursor: pointer; font-size: 12px; color: var(--text-dim); padding: 0 2px; opacity: 0.7; flex-shrink: 0; }
  .as-copy-btn:hover, .as-resolve-btn:hover { opacity: 1; }
  .study-btn.disabled-btn { opacity: 0.4; cursor: default; }
  ```

- [ ] **Step 2: Add `#autosolve-panel` div to the HTML body**

  Find in the HTML body:
  ```html
  <div class="response-area" id="responseArea"><div class="content"></div></div>
  ```
  Replace with:
  ```html
  <div class="response-area" id="responseArea"><div id="autosolve-panel"><div class="autosolve-header" id="autosolve-header"></div><div id="autosolve-rows"></div></div><div class="content"></div></div>
  ```

- [ ] **Step 3: Add `aLbeta` button**

  Find:
  ```html
  <button class="study-btn" id="autoSolveBtn" onclick="toggleAutoSolve()">Auto Solve</button>
  <button class="study-btn" id="pauseBtn" onclick="togglePause()">Pause</button>
  ```
  Replace with:
  ```html
  <button class="study-btn" id="autoSolveBtn" onclick="toggleAutoSolve()">Auto Solve</button>
  <button class="study-btn disabled-btn" disabled title="Auto-Locate (Beta) \u2014 Coming Soon">aLbeta</button>
  <button class="study-btn" id="pauseBtn" onclick="togglePause()">Pause</button>
  ```

- [ ] **Step 4: Add JS functions for the autosolve panel**

  In the main `<script>` block, find the closing `</script>` tag before `<body>`. Add these functions before it (inside the existing script block):

  ```javascript
  function showAutosolvePanel(count) {
      var panel = document.getElementById('autosolve-panel');
      var hdr = document.getElementById('autosolve-header');
      document.getElementById('autosolve-rows').textContent = '';
      hdr.textContent = count === 0 ? 'Auto Solve \u2014 all solved' : 'Auto Solve \u2014 ' + count + ' answers';
      panel.style.display = 'block';
      document.querySelector('.content').style.display = 'none';
      document.getElementById('responseArea').classList.add('visible');
  }
  function clearAutosolvePanel() {
      document.getElementById('autosolve-panel').style.display = 'none';
      document.querySelector('.content').style.display = '';
      document.getElementById('responseArea').classList.remove('visible');
  }
  function buildAnswerRow(id, latex, copyable, isMC) {
      var div = document.createElement('div');
      div.className = 'answer-row';
      div.setAttribute('data-id', String(id));
      var qnum = document.createElement('span');
      qnum.className = 'q-num';
      qnum.textContent = id + 'A:';
      var ans = document.createElement('span');
      ans.className = 'answer';
      var mathNode = document.createTextNode('\\(' + latex + '\\)');
      ans.appendChild(mathNode);
      div.appendChild(qnum);
      div.appendChild(ans);
      if (!isMC) {
          var cb = document.createElement('button');
          cb.className = 'as-copy-btn';
          cb.textContent = '\uD83D\uDCCB';
          (function(c) { cb.onclick = function() { copyAutoAnswer(c); }; })(copyable);
          div.appendChild(cb);
      }
      var rb = document.createElement('button');
      rb.className = 'as-resolve-btn';
      rb.textContent = '\u21BB';
      (function(i) { rb.onclick = function() { resolveAnswer(i); }; })(id);
      div.appendChild(rb);
      return div;
  }
  function appendAutosolveAnswer(id, latex, copyable, isMC) {
      var row = buildAnswerRow(id, latex, copyable, isMC);
      document.getElementById('autosolve-rows').appendChild(row);
      if (window.MathJax && MathJax.typesetPromise) { MathJax.typesetPromise([row]).catch(function(){}); }
  }
  function replaceAutosolveAnswer(id, latex, copyable, isMC) {
      var existing = document.querySelector('[data-id="' + id + '"]');
      var row = buildAnswerRow(id, latex, copyable, isMC);
      if (existing) { existing.parentNode.replaceChild(row, existing); }
      else { document.getElementById('autosolve-rows').appendChild(row); }
      if (window.MathJax && MathJax.typesetPromise) { MathJax.typesetPromise([row]).catch(function(){}); }
  }
  function copyAutoAnswer(text) {
      window.webkit.messageHandlers.overlay.postMessage({action:'copy', text:text});
  }
  function resolveAnswer(id) {
      window.webkit.messageHandlers.overlay.postMessage({action:'autoSolveResolve', id:id});
  }
  ```

- [ ] **Step 5: Build**

  Product → Build. No new errors expected.

- [ ] **Step 6: Commit**

  ```bash
  cd /Volumes/T7/PrestoAI
  git add PrestoAI/Views/OverlayManager-3.swift
  git commit -m "feat: OverlayManager autosolve panel HTML/CSS/JS, aLbeta button"
  ```

---

## Task 8: OverlayManager — Swift methods + new switch cases

**Files:**
- Modify: `PrestoAI/Views/OverlayManager-3.swift`

- [ ] **Step 1: Add `case "autoSolveResolve"` and `case "copy"` to `userContentController` switch**

  Verify first: `grep -n '"copy"' PrestoAI/Views/OverlayManager-3.swift` — expected: no results (the existing switch does not have a copy case). If a copy case already exists, skip adding it.

  Find the existing switch in `userContentController(_:didReceive:)`. After `case "suggestionDismiss": dismissPopup(); onSuggestionDismiss?()`, add before `default: break`:

  ```swift
  case "autoSolveResolve":
      if let id = dict["id"] as? Int {
          StudyCoordinator.shared.resolveQuestion(id: id)
      }
  case "copy":
      if let text = dict["text"] as? String {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
      }
  ```

- [ ] **Step 2: Add the four auto-solve Swift methods**

  After the `showStudySummary` method (search for `func showStudySummary`), add:

  ```swift
  // MARK: - Auto Solve Results

  func showAutoSolveResults(count: Int) {
      DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          self.expandStudyBar()
          self.webView?.evaluateJavaScript("showAutosolvePanel(\(count))", completionHandler: nil)
      }
  }

  func appendAutoSolveAnswer(id: Int, latex: String, copyable: String, isMC: Bool) {
      DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          let eLat = latex
              .replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "'", with: "\\'")
              .replacingOccurrences(of: "\n", with: "\\n")
          let eCopy = copyable
              .replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "'", with: "\\'")
          let js = "appendAutosolveAnswer(\(id), '\(eLat)', '\(eCopy)', \(isMC ? "true" : "false"))"
          self.webView?.evaluateJavaScript(js, completionHandler: nil)
      }
  }

  func replaceAutoSolveAnswer(id: Int, latex: String, copyable: String, isMC: Bool) {
      DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          let eLat = latex
              .replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "'", with: "\\'")
              .replacingOccurrences(of: "\n", with: "\\n")
          let eCopy = copyable
              .replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "'", with: "\\'")
          let js = "replaceAutosolveAnswer(\(id), '\(eLat)', '\(eCopy)', \(isMC ? "true" : "false"))"
          self.webView?.evaluateJavaScript(js, completionHandler: nil)
      }
  }

  func clearAutoSolveResults() {
      DispatchQueue.main.async { [weak self] in
          self?.webView?.evaluateJavaScript("clearAutosolvePanel()", completionHandler: nil)
      }
  }
  ```

- [ ] **Step 3: Build — errors should only be in PrestoAIApp now**

  Product → Build.

- [ ] **Step 4: Commit**

  ```bash
  cd /Volumes/T7/PrestoAI
  git add PrestoAI/Views/OverlayManager-3.swift
  git commit -m "feat: OverlayManager autosolve Swift methods, autoSolveResolve + copy switch cases"
  ```

---

## Task 9: PrestoAIApp — Replace all wiring

**Files:**
- Modify: `PrestoAI/PrestoAIApp.swift`

- [ ] **Step 1: Set `overlayManager` on `StudyCoordinator` in `setupServices()`**

  Find the line `overlayManager = OverlayManager()`. Add immediately after:
  ```swift
  StudyCoordinator.shared.overlayManager = overlayManager
  ```

- [ ] **Step 2: Replace `setupStudyModeCallbacks()` entirely**

  Find the entire `private func setupStudyModeCallbacks()` function and replace with:

  ```swift
  private func setupStudyModeCallbacks() {
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

      coord.onSessionEnded = { [weak self] summary in
          self?.overlayManager?.dismiss()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              self?.overlayManager?.showStudySummary(text: summary)
          }
          self?.refreshMenuState()
      }

      coord.onSuggestionAccepted = { [weak self] display in
          self?.overlayManager?.expandStudyBar()
          self?.overlayManager?.appendChunk(display)
          self?.overlayManager?.signalStreamEnd()
      }

      overlayManager?.onSuggestionDismiss = {
          StudyCoordinator.shared.dismissCurrentSuggestion()
      }

      let cancellable = StudyCoordinator.shared.$sessionDurationText.sink { [weak self] _ in
          DispatchQueue.main.async { self?.refreshMenuState() }
      }
      objc_setAssociatedObject(self, "coordDurationCancellable", cancellable, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }
  ```

- [ ] **Step 3: Replace `toggleStudyMode()`**

  Find `@objc private func toggleStudyMode()` and replace its body:

  ```swift
  @objc private func toggleStudyMode() {
      if AppStateManager.shared.isOffline {
          overlayManager?.showError("Unable to connect to Presto AI servers. Check your internet connection and try again.")
          return
      }
      let coord = StudyCoordinator.shared
      if coord.isActive {
          coord.endSession()
      } else {
          if AppStateManager.shared.currentState != .paid { showPaywall(); return }
          coord.startSession()
          if coord.isActive { onStudyModeActivated() }
      }
      refreshMenuState()
  }
  ```

- [ ] **Step 4: Replace overlay callbacks in `onStudyModeActivated()`**

  Find and replace the study-related overlay callbacks:
  ```swift
  // Find:
  overlayManager?.onStudyPauseToggle = {
      let sm = StudyModeManager.shared
      sm.isPaused ? sm.resume() : sm.pause()
  }
  overlayManager?.onAutoSolveToggle = {
      let am = AutoSolveManager.shared
      if am.isActive {
          am.deactivate()
      } else {
          let sid = StudyModeManager.shared.currentSessionId ?? UUID().uuidString
          am.activate(sessionId: sid)
      }
  }
  overlayManager?.onStudyStop = { [weak self] in
      StudyModeManager.shared.deactivate()
  }
  // Replace with:
  overlayManager?.onStudyPauseToggle = {
      let c = StudyCoordinator.shared
      c.isPaused ? c.resume() : c.pause()
  }
  overlayManager?.onAutoSolveToggle = {
      StudyCoordinator.shared.toggleAutoSolve()
  }
  overlayManager?.onStudyStop = {
      StudyCoordinator.shared.endSession()
  }
  ```

- [ ] **Step 5: Update `refreshMenuState()` to use `StudyCoordinator`**

  Find the block referencing `StudyModeManager.shared` in `refreshMenuState()`:
  ```swift
  // Find:
  let studyMode = StudyModeManager.shared
  if studyMode.isActive {
      studyModeMenuItem?.title = "Study Mode (Active \(studyMode.sessionDurationText))"
  } else {
      studyModeMenuItem?.title = "Study Mode"
  }
  studyModeMenuItem?.isEnabled = state.currentState == .paid || studyMode.isActive
  // Replace with:
  let coord = StudyCoordinator.shared
  if coord.isActive {
      studyModeMenuItem?.title = "Study Mode (Active \(coord.sessionDurationText))"
  } else {
      studyModeMenuItem?.title = "Study Mode"
  }
  studyModeMenuItem?.isEnabled = state.currentState == .paid || coord.isActive
  ```

- [ ] **Step 6: Replace `buildSessionContextPrompt` and `recordQuestionAsked` call sites**

  In `onStudyModeActivated()`, find:
  ```swift
  StudyModeManager.shared.recordQuestionAsked()
  ```
  Replace with:
  ```swift
  StudyCoordinator.shared.recordQuestionAsked()
  ```

  Find:
  ```swift
  let contextPrefix = StudyModeManager.shared.buildSessionContextPrompt() ?? ""
  ```
  Replace with:
  ```swift
  let contextPrefix = StudyCoordinator.shared.buildSessionContextPrompt() ?? ""
  ```

- [ ] **Step 7: Remove the old `$currentSuggestion` Combine sink**

  Find and delete the entire block:
  ```swift
  let cancellable = studyMode.$currentSuggestion.sink { [weak self] suggestion in
      guard let suggestion = suggestion else { return }
      self?.overlayManager?.showStudySuggestion(text: suggestion.suggestionText)
  }
  objc_setAssociatedObject(self, "studySuggestionCancellable", cancellable, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  ```

- [ ] **Step 8: Build — expect 0 errors**

  Product → Build (⌘B). Expected: successful build, 0 errors.

- [ ] **Step 9: Commit**

  ```bash
  cd /Volumes/T7/PrestoAI
  git add PrestoAI/PrestoAIApp.swift
  git commit -m "feat: PrestoAIApp wired to StudyCoordinator, remove StudyModeManager/AutoSolveManager refs"
  ```

---

## Task 10: Smoke Test + Push

- [ ] **Step 1: Full clean build**

  Product → Clean Build Folder (⇧⌘K), then Build (⌘B).
  Expected: 0 errors, 0 warnings from new code.

- [ ] **Step 2: Run and verify Study Mode starts**

  Launch app → ⌘⇧S → verify study bar appears with green dot and timer.
  After 3 seconds, console should print: `[Coordinator] Session started, N questions found, memory initialized`

- [ ] **Step 3: Verify Smart Suggestion cycle**

  Open a homework page → wait ~20 seconds → verify suggestion popup "Want to solve Q1? ..." appears.
  Click Yes → answer streams into study bar.

- [ ] **Step 4: Verify Auto Solve**

  Click Auto Solve button → button text becomes "Stop Solving" → answers appear in overlay with LaTeX rendered, 📋 and ↻ buttons visible.
  Click ↻ on one answer → that answer re-fetches and updates in place.
  Click 📋 → answer text copied to clipboard.
  Click Stop Solving → panel clears, button resets to "Auto Solve".

- [ ] **Step 5: Verify aLbeta is greyed and non-functional**

  Button appears between Auto Solve and Pause, visibly dimmer (opacity 0.4). Clicking it does nothing.

- [ ] **Step 6: Verify Stop**

  Click Stop → overlay dismisses, session summary appears briefly.

- [ ] **Step 7: Push source**

  ```bash
  cd /Volumes/T7/PrestoAI
  git push source main
  ```

---

## Reference

- Spec: `docs/superpowers/specs/2026-03-24-study-coordinator-rewrite-design.md`
- Context: `CONTEXT.md`
- OverlayManager study bar HTML: `PrestoAI/Views/OverlayManager-3.swift` ~line 1460
- `userContentController` switch: `PrestoAI/Views/OverlayManager-3.swift` ~line 462
- APIService auto-solve methods: `PrestoAI/Services/APIService.swift` ~line 499
- Backend auto-solve handler: `Presto backend/main.py` ~line 1414
