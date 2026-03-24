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

    // MARK: - Identify

    private func performInitialIdentify() {
        guard isActive else { return }
        Task { [weak self] in
            guard let self = self else { return }
            guard let (cgImage, base64) = await self.captureScreen() else { return }
            guard self.isActive else { return }
            let (compressed, _) = ImageCompressor.compress(base64)
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
            let (compressed, _) = ImageCompressor.compress(base64)
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
}
