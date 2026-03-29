import AppKit
import Vision
import Combine
import CoreGraphics

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
    static let sensitiveContentKeywords: [String] = [
        "ssn", "social security", "credit card", "password"
    ]

    var userExclusions: Set<String> = []

    static func isExcluded(appName: String, windowTitle: String, userExclusions: Set<String>) -> Bool {
        let all = defaultExcludedApps.union(userExclusions)
        if all.contains(appName) { return true }
        let lower = windowTitle.lowercased()
        return excludedWindowTitleKeywords.contains { lower.contains($0.lowercased()) }
    }

    func isCurrentAppExcluded(appName: String) -> Bool {
        PrivacyFilter.defaultExcludedApps.union(userExclusions).contains(appName)
    }

    func isCurrentWindowSensitive(windowTitle: String) -> Bool {
        let lower = windowTitle.lowercased()
        return PrivacyFilter.excludedWindowTitleKeywords.contains { lower.contains($0.lowercased()) }
    }

    func containsSensitiveContent(_ text: String) -> Bool {
        let lower = text.lowercased()
        return PrivacyFilter.sensitiveContentKeywords.contains { lower.contains($0) }
    }
}

// MARK: - AutoSolveAnswer (legacy compat for old overlay calls)

struct AutoSolveAnswer {
    let id: String
    var latex: String
    var copyable: String
    var isMC: Bool
    var failed: Bool
    var solving: Bool
    var page: Int
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
    var onSessionEnded: ((String) -> Void)?
    var onSuggestionAccepted: ((String) -> Void)?

    // MARK: OverlayManager reference (set by PrestoAIApp)
    weak var overlayManager: OverlayManager?

    // MARK: V2 Components
    private var contentDetector = ContentDetector()
    private var solverEngine = SolverEngine()
    private var privacyFilter = PrivacyFilter()

    // MARK: Session
    private var session: StudySession?
    private var memory: SessionMemory?
    private(set) var currentMode: StudyMode = .learn

    // MARK: Capture Decision
    private var lastCaptureTime: Date = .distantPast
    private var lastWindowTitle: String = ""
    private var lastAppName: String = ""
    private var userIsActivelyTyping = false

    // MARK: Modes
    private var isIdentifyComplete = false

    // MARK: OS Monitors
    private var captureTimer: Timer?
    private var durationTimer: Timer?
    private var typingTimer: Timer?
    private var keyEventMonitor: Any?
    private var appObserver: NSObjectProtocol?
    private var isIdentifyInFlight = false
    private var isPrivateAppDetected = false

    // MARK: Idle Nudge
    private var idleTimer: Timer?
    private var lastUserActivityTime: Date = Date()
    private var hasShownIdleNudge = false
    private var idleNudgeCooldownUntil: Date = .distantPast

    // MARK: Legacy compat
    private var solvedAnswers: [AutoSolveAnswer] = []
    private var autoSolveActive = false
    private var suggestionTimer: Timer?
    private var pendingAutoSolve = false
    private var lastNotificationTime: Date = .distantPast
    private var consecutiveDismissals = 0

    // MARK: Onboarding
    private var hasShownOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "studyModeOnboardingShown") }
        set { UserDefaults.standard.set(newValue, forKey: "studyModeOnboardingShown") }
    }

    // MARK: Settings

    private var detectInterval: TimeInterval {
        currentMode == .solve ? 3.0 : 5.0
    }

    private init() {}

    // MARK: - Public API

    func startSession() {
        guard AppStateManager.shared.currentState == .paid else { return }
        guard !isActive else { return }
        if !hasShownOnboarding { onNeedsOnboarding?(); return }

        let newSession = StudySession(id: UUID().uuidString, startedAt: Date())
        session = newSession
        memory = SessionMemory()
        contentDetector.reset()
        solverEngine.sessionId = newSession.id
        solverEngine.cancelAll()
        privacyFilter.userExclusions = []
        currentMode = .learn
        isIdentifyComplete = false
        pendingAutoSolve = false
        solvedAnswers = []

        isActive = true
        isPaused = false
        consecutiveDismissals = 0
        isPrivateAppDetected = false
        isIdentifyInFlight = false

        startOSMonitors()
        startDurationTimer()
        startIdleDetection()
        // NOTE: Do NOT start content detection timer here.
        // It starts after initial identify completes to avoid duplicate calls.

        // 3-second settle delay then initial identify
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.performInitialIdentify()
        }

        Analytics.shared.track("study.sessionStarted")
        print("[Coordinator] Session started — \(newSession.id)")
    }

    func activateAfterOnboarding() {
        hasShownOnboarding = true
        startSession()
    }

    func endSession() {
        guard isActive else { return }

        // Record mode time
        memory?.recordModeTime(mode: currentMode)

        let summary = buildSessionSummary()
        captureTimer?.invalidate(); captureTimer = nil
        durationTimer?.invalidate(); durationTimer = nil
        typingTimer?.invalidate(); typingTimer = nil
        suggestionTimer?.invalidate(); suggestionTimer = nil
        idleTimer?.invalidate(); idleTimer = nil
        if let m = keyEventMonitor { NSEvent.removeMonitor(m); keyEventMonitor = nil }
        if let o = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(o); appObserver = nil }

        solverEngine.cancelAll()

        // Analytics: study.sessionEnded (before session/memory are cleared)
        let sessionDuration = session.map { "\(Int(Date().timeIntervalSince($0.startedAt)))" } ?? "0"
        let questionsCount = "\(memory?.allQuestionTextFragments().count ?? 0)"
        Analytics.shared.track("study.sessionEnded", params: [
            "durationSeconds": sessionDuration,
            "questionsIdentified": questionsCount
        ])

        // Report session
        if let s = session { reportSessionEnd(s) }

        // Show summary in overlay
        if let mem = memory {
            let duration = sessionDurationText
            let solved = mem.solvedCount
            let pages = mem.totalPagesDetected
            let topics = mem.conceptsCovered
            overlayManager?.showStudySessionSummary(
                duration: duration, solved: solved, pages: pages, topics: topics
            )
        }

        session = nil
        memory = nil
        isActive = false
        isPaused = false
        isIdentifyInFlight = false
        isIdentifyComplete = false
        pendingAutoSolve = false
        autoSolveActive = false
        solvedAnswers = []
        sessionDurationText = ""
        consecutiveDismissals = 0
        isPrivateAppDetected = false

        onSessionEnded?(summary)
        print("[Coordinator] Session ended")
    }

    func pause() {
        isPaused = true
        captureTimer?.invalidate(); captureTimer = nil
        overlayManager?.updateStudyStatus(text: "Paused", dotState: "paused")
        print("[Coordinator] Paused")
    }

    func resume() {
        isPaused = false
        startContentDetectionTimer()
        overlayManager?.updateStudyStatus(text: "Study Mode", dotState: "active")
        print("[Coordinator] Resumed")
    }

    func recordQuestionAsked() { session?.questionsAsked += 1 }

    func buildSessionContextPrompt() -> String? {
        guard let s = session, let mem = memory else { return nil }
        let mins = Int(Date().timeIntervalSince(s.startedAt) / 60)

        var context = "Study Mode active \(mins) min."

        if !mem.globalContext.isEmpty {
            context += " Course: \(mem.globalContext)."
        }

        // Include question texts so the model knows what the student is working on
        let questionTexts = mem.allQuestionsOrdered.prefix(6).map { q in
            "Q\(q.id): \(String(q.questionText.prefix(100)))"
        }
        if !questionTexts.isEmpty {
            context += " Current questions: " + questionTexts.joined(separator: "; ")
        }

        if !mem.conceptsCovered.isEmpty {
            context += " Topics covered: \(mem.conceptsCovered.joined(separator: ", "))."
        }

        return context
    }

    // MARK: - Mode Switching

    func switchMode(to mode: StudyMode) {
        guard isActive else { return }
        memory?.recordModeTime(mode: currentMode)
        currentMode = mode
        Analytics.shared.track("study.modeSwitch", params: ["toMode": "\(mode)"])

        // Restart detection timer with new interval
        captureTimer?.invalidate()
        startContentDetectionTimer()

        switch mode {
        case .solve:
            // Trigger batch solve on all unsolved
            if isIdentifyComplete {
                performBatchSolve()
            }
            overlayManager?.resizeForCurrentContent()
            print("[Coordinator] Switched to Solve mode")

        case .learn:
            // Stop batch solving, let in-flight finish
            print("[Coordinator] Switched to Learn mode")
        }
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

    private func startContentDetectionTimer() {
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: detectInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isActive, !self.isPaused else { return }
            Task { [weak self] in await self?.runContentDetection() }
        }
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateDurationText()
        }
        updateDurationText()
    }

    private func handleAppSwitch(appName: String) {
        guard isActive, !isPaused else { return }
        session?.appsVisited.insert(appName)
        let title = getCurrentWindowTitle()
        if PrivacyFilter.isExcluded(appName: appName, windowTitle: title, userExclusions: []) {
            isPrivateAppDetected = true
            overlayManager?.updateStudyStatus(text: "Paused — private app", dotState: "paused")
            return
        }
        if isPrivateAppDetected {
            isPrivateAppDetected = false
            overlayManager?.updateStudyStatus(text: "Study Mode", dotState: "active")
        }
    }

    // MARK: - Content Detection (V2)

    @MainActor
    private func runContentDetection() async {
        guard isActive, !isPaused, !isPrivateAppDetected, !isIdentifyInFlight else { return }

        let result = await contentDetector.detect(
            privacyFilter: privacyFilter,
            sessionMemory: memory ?? SessionMemory()
        )

        switch result {
        case .unchanged:
            break

        case .blocked(let reason):
            switch reason {
            case .privateApp:
                isPrivateAppDetected = true
                await MainActor.run {
                    overlayManager?.updateStudyStatus(text: "Paused — private app", dotState: "paused")
                }
            case .sensitiveWindow:
                await MainActor.run {
                    overlayManager?.updateStudyStatus(text: "Paused — sensitive window", dotState: "paused")
                }
            case .sensitiveContent:
                break // silently skip
            }

        case .newContent(let ocrPreview, _, let base64, let isNewPage):
            guard isActive else { return }
            if isNewPage {
                await MainActor.run { [weak self] in
                    self?.memory?.currentPage += 1
                    self?.memory?.totalPagesDetected += 1
                }
            }
            await identifyNewContent(base64: base64, ocrPreview: ocrPreview, isNewPage: isNewPage)
        }
    }

    // MARK: - Identify

    private func performInitialIdentify() {
        guard isActive, !isIdentifyInFlight else { return }
        isIdentifyInFlight = true
        overlayManager?.updateStudyStatus(text: "Identifying...", dotState: "solving")

        // Show shimmer placeholders immediately — don't wait for API
        overlayManager?.showIdentifyingPlaceholders(count: 4)

        Task { [weak self] in
            guard let self = self else { return }
            defer {
                Task { @MainActor in
                    self.isIdentifyInFlight = false
                    // Start content detection timer AFTER initial identify completes
                    if self.isActive {
                        self.startContentDetectionTimer()
                    }
                }
            }
            guard let (_, base64) = await self.contentDetector.captureScreen() else { return }
            guard self.isActive else { return }

            let (compressed, _) = ImageCompressor.compress(base64)
            await self.identifyAndPopulate(image: compressed, ocrPreview: "", pageNumber: 1)
        }
    }

    @MainActor
    private func identifyNewContent(base64: String, ocrPreview: String, isNewPage: Bool) async {
        guard !isIdentifyInFlight else { return }
        isIdentifyInFlight = true
        defer { isIdentifyInFlight = false }

        let (compressed, _) = ImageCompressor.compress(base64)
        let pageNum = memory?.currentPage ?? 1
        await identifyAndPopulate(image: compressed, ocrPreview: ocrPreview, pageNumber: pageNum)
    }

    private func identifyAndPopulate(image: String, ocrPreview: String, pageNumber: Int) async {
        guard let mem = memory else { return }
        let existingIds = Array(mem.questions.keys)

        do {
            let result = try await APIService.shared.studyIdentify(
                image: image,
                ocrPreview: ocrPreview,
                sessionId: session?.id ?? "",
                pageNumber: pageNumber,
                existingQuestionIds: existingIds
            )

            await MainActor.run { [weak self] in
                guard let self = self, self.isActive, let mem = self.memory else { return }

                // Update global context
                if !result.globalContext.isEmpty {
                    mem.globalContext = result.globalContext
                }
                mem.documentType = result.documentType

                // Add new questions
                var newCount = 0
                for q in result.questions {
                    guard mem.questions[q.id] == nil else { continue }
                    let record = QuestionRecord(
                        id: q.id,
                        questionText: q.questionText,
                        answerBoxHint: q.answerBoxHint,
                        detectedPage: pageNumber,
                        questionType: q.questionType,
                        positionOnPage: q.positionOnPage,
                        topic: q.topic,
                        difficulty: q.estimatedDifficulty
                    )
                    mem.addQuestion(record)
                    newCount += 1
                }

                self.isIdentifyComplete = true
                print("[Coordinator] Identified \(newCount) new questions (total: \(mem.totalCount))")

                // Update content detector known fragments
                self.contentDetector.registerKnownFragments(mem.allQuestionTextFragments())

                // Only update visible UI in Solve mode
                if self.currentMode == .solve {
                    if newCount > 0 {
                        self.performBatchSolve()
                    }
                    self.renderStudyUI()
                } else {
                    // Learn mode — silently note new questions, no resize
                    if newCount > 0 {
                        self.overlayManager?.updateStudyStatus(
                            text: "\(mem.totalCount) questions found",
                            dotState: "active"
                        )
                    }
                }
            }
        } catch {
            print("[Coordinator] Identify failed: \(error)")
            await MainActor.run { [weak self] in
                self?.overlayManager?.updateStudyStatus(text: "Could not identify questions", dotState: "active")
            }
        }
    }

    // MARK: - Batch Solve (V2)

    private func performBatchSolve() {
        guard let mem = memory else { return }
        // Only pick up pending or failed — skip questions already being solved
        let unsolved = mem.unsolvedQuestions.filter { $0.state == .pending || $0.state == .failed }
        guard !unsolved.isEmpty else {
            overlayManager?.updateStudyStatus(text: "All solved", dotState: "active")
            renderStudyUI()
            return
        }

        // Update status
        let total = mem.totalCount
        let solved = mem.solvedCount
        overlayManager?.updateStudyStatus(
            text: "Solving \(solved) of \(total)...",
            dotState: "solving"
        )

        renderStudyUI()

        solverEngine.batchSolve(questions: unsolved, memory: mem) { [weak self] questionId, result in
            guard let self = self, let mem = self.memory else { return }

            switch result {
            case .solved(let answer, let topic, _):
                mem.markSolved(questionId, answer: answer)
                if let topic = topic {
                    mem.questions[questionId]?.topic = topic
                }

            case .failed:
                mem.markFailed(questionId)
            }

            // Update status bar
            let total = mem.totalCount
            let solved = mem.solvedCount
            let inFlight = self.solverEngine.solversInFlight

            if inFlight == 0 {
                let statusText = mem.failedQuestions.isEmpty ? "All solved" : "\(solved) of \(total) solved"
                self.overlayManager?.updateStudyStatus(text: statusText, dotState: "active")
            } else {
                self.overlayManager?.updateStudyStatus(
                    text: "Solving \(solved) of \(total)...",
                    dotState: "solving"
                )
            }

            // Update only the changed row — not the full list
            if let question = mem.questions[questionId] {
                self.overlayManager?.updateQuestionRow(question)
            }
            self.overlayManager?.resizeForCurrentContent()
        }
    }

    // MARK: - Render UI

    private func renderStudyUI() {
        guard let mem = memory else { return }
        let questions = mem.allQuestionsOrdered

        let total = mem.totalCount
        let solved = mem.solvedCount
        let inFlight = solverEngine.solversInFlight

        let statusText: String
        let dotState: String
        if isPaused {
            statusText = "Paused"
            dotState = "paused"
        } else if inFlight > 0 {
            statusText = "Solving \(solved) of \(total)..."
            dotState = "solving"
        } else if total > 0 && solved == total {
            statusText = "All solved"
            dotState = "active"
        } else if total > 0 {
            statusText = "\(solved) of \(total) solved"
            dotState = "active"
        } else {
            statusText = "Study Mode"
            dotState = "active"
        }

        overlayManager?.refreshStudyUI(statusText: statusText, dotState: dotState, questions: questions)
    }

    // MARK: - Retry Single Question

    func resolveQuestion(id: String) {
        guard let mem = memory else { return }
        mem.resetForRetry(id)
        // Update only the retrying row to show solving state
        if let question = mem.questions[id] {
            overlayManager?.updateQuestionRow(question)
        }

        solverEngine.solveSingle(questionId: id, memory: mem) { [weak self] questionId, result in
            guard let self = self, let mem = self.memory else { return }
            switch result {
            case .solved(let answer, let topic, _):
                mem.markSolved(questionId, answer: answer)
                if let topic = topic { mem.questions[questionId]?.topic = topic }
            case .failed:
                mem.markFailed(questionId)
            }
            if let question = mem.questions[questionId] {
                self.overlayManager?.updateQuestionRow(question)
            }
        }
    }

    // MARK: - Step Loading

    func loadStepsForQuestion(id: String) {
        guard let mem = memory else { return }
        solverEngine.loadSteps(questionId: id, memory: mem) { [weak self] questionId, steps in
            if let steps = steps {
                self?.overlayManager?.updateQuestionSteps(questionId: questionId, steps: steps)
            }
        }
    }

    // MARK: - Legacy Auto Solve Toggle (for backward compat)

    func toggleAutoSolve() {
        if currentMode == .solve && isIdentifyComplete {
            performBatchSolve()
        } else {
            switchMode(to: .solve)
        }
    }

    // MARK: - Smart Suggestions (legacy)

    func handleUserAcceptedSuggestion(questionId: String) {
        guard let mem = memory, let q = mem.questions[questionId] else { return }
        session?.suggestionsAccepted += 1
        consecutiveDismissals = 0

        solverEngine.solveSingle(questionId: questionId, memory: mem) { [weak self] qId, result in
            guard let self = self, let mem = self.memory else { return }
            switch result {
            case .solved(let answer, let topic, _):
                mem.markSolved(qId, answer: answer)
                if let topic = topic { mem.questions[qId]?.topic = topic }
                let display = "**Q\(qId):** \(q.questionText)\n\n**Answer:** \(answer.latex)"
                self.onSuggestionAccepted?(display)
            case .failed:
                mem.markFailed(qId)
            }
        }
    }

    func dismissCurrentSuggestion() {
        consecutiveDismissals += 1
    }

    // MARK: - Intent Detection

    enum LearnIntent {
        case explain(questionId: String)
        case check(questionId: String, userAttempt: String)
        case quiz(topics: [String])
        case solveOne(questionId: String)
        case freeform(text: String)
    }

    func detectIntent(_ text: String) -> LearnIntent {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

        if lower.hasPrefix("quiz") || lower.hasPrefix("test me") || lower.hasPrefix("practice") {
            return .quiz(topics: extractTopics(from: lower))
        }

        if lower.hasPrefix("check") || lower.hasPrefix("verify") || lower.hasPrefix("is this right") || lower.hasPrefix("did i get") {
            if let (qId, attempt) = extractCheckData(from: text) {
                return .check(questionId: qId, userAttempt: attempt)
            }
        }

        if lower.hasPrefix("explain") || lower.hasPrefix("help with") || lower.hasPrefix("how do i solve") || lower.hasPrefix("how to solve") || lower.hasPrefix("what is") {
            if let qId = extractQuestionId(from: lower) {
                return .explain(questionId: qId)
            }
        }

        if lower.hasPrefix("solve") || lower.hasPrefix("answer") || lower.hasPrefix("what's the answer") || lower.hasPrefix("whats the answer") {
            if let qId = extractQuestionId(from: lower) {
                return .solveOne(questionId: qId)
            }
        }

        if let qId = extractQuestionId(from: lower) {
            return .explain(questionId: qId)
        }

        return .freeform(text: text)
    }

    private func extractQuestionId(from text: String) -> String? {
        guard let mem = memory else { return nil }
        let sortedIds = mem.questions.keys.sorted { $0.count > $1.count }
        for id in sortedIds {
            let patterns = [id.lowercased(), "q" + id.lowercased(), "question " + id.lowercased(), "#" + id.lowercased()]
            for pattern in patterns {
                if text.lowercased().contains(pattern) { return id }
            }
        }
        return nil
    }

    private func extractCheckData(from text: String) -> (String, String)? {
        guard let qId = extractQuestionId(from: text.lowercased()) else { return nil }
        let lower = text.lowercased()
        if let range = lower.range(of: qId.lowercased()) {
            var afterId = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if afterId.hasPrefix(":") || afterId.hasPrefix("-") || afterId.hasPrefix(",") {
                afterId = String(afterId.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if !afterId.isEmpty { return (qId, afterId) }
        }
        return (qId, text)
    }

    private func extractTopics(from text: String) -> [String] {
        guard let mem = memory else { return [] }
        let prefixes = ["quiz me on ", "quiz on ", "test me on ", "practice "]
        for prefix in prefixes {
            if text.hasPrefix(prefix) {
                let topic = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !topic.isEmpty { return [topic] }
            }
        }
        if !mem.conceptsCovered.isEmpty { return mem.conceptsCovered }
        return Array(Set(mem.questions.values.compactMap { $0.topic }))
    }

    // MARK: - Learn Intent Handlers

    func handleExplainIntent(questionId: String) {
        guard let mem = memory, let question = mem.questions[questionId] else {
            overlayManager?.updateStudyStatus(text: "Question \(questionId) not found", dotState: "active")
            return
        }
        overlayManager?.expandStudyBar()
        overlayManager?.updateStudyStatus(text: "Explaining Q\(questionId)...", dotState: "solving")
        overlayManager?.showLearnLoading()

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await APIService.shared.studyExplain(
                    sessionId: self.session?.id ?? "",
                    questionId: questionId,
                    questionText: question.questionText,
                    globalContext: mem.globalContext,
                    previouslyExplainedConcepts: mem.conceptsCovered
                )
                if !response.conceptName.isEmpty && !mem.conceptsCovered.contains(response.conceptName) {
                    mem.conceptsCovered.append(response.conceptName)
                }
                await MainActor.run { [weak self] in
                    self?.overlayManager?.updateStudyStatus(text: "Study Mode", dotState: "active")
                    self?.overlayManager?.showExplainCard(ConceptExplanation(
                        conceptName: response.conceptName,
                        conceptExplanation: response.conceptExplanation,
                        formulaLatex: response.formulaLatex,
                        strategy: response.strategy,
                        similarExample: nil,
                        commonMistakes: response.commonMistakes
                    ))
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.overlayManager?.updateStudyStatus(text: "Explain failed", dotState: "active")
                    self?.overlayManager?.showLearnError("Could not explain Q\(questionId). Try again.")
                }
            }
        }
    }

    func handleCheckIntent(questionId: String, userAttempt: String) {
        guard let mem = memory, let question = mem.questions[questionId] else {
            overlayManager?.updateStudyStatus(text: "Question \(questionId) not found", dotState: "active")
            return
        }
        overlayManager?.expandStudyBar()
        overlayManager?.updateStudyStatus(text: "Checking Q\(questionId)...", dotState: "solving")
        overlayManager?.showLearnLoading()

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await APIService.shared.studyCheck(
                    sessionId: self.session?.id ?? "",
                    questionId: questionId,
                    questionText: question.questionText,
                    userAttemptText: userAttempt,
                    userAttemptImage: nil,
                    globalContext: mem.globalContext
                )
                await MainActor.run { [weak self] in
                    self?.overlayManager?.updateStudyStatus(text: "Study Mode", dotState: "active")
                    self?.overlayManager?.showCheckFeedback(WorkCheckFeedback(
                        isCorrect: response.isCorrect,
                        correctnessPercentage: response.correctnessPercentage,
                        feedback: response.feedback,
                        errorStep: response.errorStep,
                        errorType: response.errorType,
                        correctFromError: response.correctFromError,
                        encouragement: response.encouragement
                    ))
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.overlayManager?.updateStudyStatus(text: "Check failed", dotState: "active")
                    self?.overlayManager?.showLearnError("Could not check your work. Try again.")
                }
            }
        }
    }

    func handleQuizIntent(topics: [String]) {
        guard let mem = memory else { return }
        overlayManager?.expandStudyBar()
        overlayManager?.updateStudyStatus(text: "Generating quiz...", dotState: "solving")
        overlayManager?.showLearnLoading()

        let sampleTexts = Array(mem.allQuestionsOrdered.prefix(5).map { $0.questionText })

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await APIService.shared.studyQuiz(
                    sessionId: self.session?.id ?? "",
                    topics: topics.isEmpty ? mem.conceptsCovered : topics,
                    difficulty: "medium",
                    count: 3,
                    excludeQuestions: Array(mem.questions.keys),
                    sampleQuestions: sampleTexts,
                    globalContext: mem.globalContext
                )
                await MainActor.run { [weak self] in
                    self?.overlayManager?.updateStudyStatus(text: "Quiz ready", dotState: "active")
                    self?.overlayManager?.showQuizCard(response.quizQuestions)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.overlayManager?.updateStudyStatus(text: "Quiz failed", dotState: "active")
                    self?.overlayManager?.showLearnError("Could not generate quiz. Try again.")
                }
            }
        }
    }

    func handleSolveOneIntent(questionId: String) {
        guard let mem = memory else { return }
        overlayManager?.expandStudyBar()
        overlayManager?.updateStudyStatus(text: "Solving Q\(questionId)...", dotState: "solving")
        overlayManager?.showLearnLoading()

        solverEngine.solveSingle(questionId: questionId, memory: mem) { [weak self] qId, result in
            guard let self = self, let mem = self.memory else { return }
            switch result {
            case .solved(let answer, let topic, _):
                mem.markSolved(qId, answer: answer)
                if let topic = topic { mem.questions[qId]?.topic = topic }
                self.overlayManager?.updateStudyStatus(text: "Study Mode", dotState: "active")
                self.renderStudyUI()
            case .failed:
                mem.markFailed(qId)
                self.overlayManager?.updateStudyStatus(text: "Solve failed", dotState: "active")
                self.overlayManager?.showLearnError("Could not solve Q\(qId). Try again.")
            }
        }
    }

    // MARK: - Idle Nudge

    func recordUserActivity() {
        lastUserActivityTime = Date()
        hasShownIdleNudge = false
    }

    private func startIdleDetection() {
        idleTimer?.invalidate()
        lastUserActivityTime = Date()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.checkIdleState()
        }
    }

    private func checkIdleState() {
        guard isActive, !isPaused, currentMode == .learn else { return }
        guard Date() > idleNudgeCooldownUntil else { return }
        guard !hasShownIdleNudge else { return }

        let idleDuration = Date().timeIntervalSince(lastUserActivityTime)
        guard idleDuration >= 90 else { return }

        guard let mem = memory else { return }
        guard let nextQ = mem.unsolvedQuestions.first else { return }

        hasShownIdleNudge = true
        overlayManager?.updateStudyStatus(text: "Need help with Q\(nextQ.id)?", dotState: "active")

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.hasShownIdleNudge else { return }
            self.overlayManager?.updateStudyStatus(text: "Study Mode", dotState: "active")
            self.idleNudgeCooldownUntil = Date().addingTimeInterval(300)
        }
    }

    // MARK: - Helpers

    private func updateDurationText() {
        guard let s = session else { return }
        let mins = Int(Date().timeIntervalSince(s.startedAt) / 60)
        if mins < 1 { sessionDurationText = "Just started" }
        else if mins < 60 { sessionDurationText = "\(mins) min" }
        else { sessionDurationText = "\(mins / 60)h \(mins % 60)m" }
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
        let solved = memory?.solvedCount ?? 0
        return "\(mins)min session, solved \(solved) question\(solved == 1 ? "" : "s")"
    }

    private func reportSessionEnd(_ s: StudySession) {
        let body: [String: Any] = [
            "session_id": s.id,
            "device_id": AppStateManager.shared.deviceID,
            "duration_seconds": Int(Date().timeIntervalSince(s.startedAt)),
            "captures_count": s.capturesCount,
            "questions_asked": s.questionsAsked,
            "questions_solved": memory?.solvedCount ?? 0,
            "pages_detected": memory?.totalPagesDetected ?? 1,
            "mode_time_solve_seconds": memory?.modeTimeSolveSeconds ?? 0,
            "mode_time_learn_seconds": memory?.modeTimeLearnSeconds ?? 0,
            "topics_covered": memory?.conceptsCovered ?? []
        ]
        Task { try? await APIService.shared.reportStudySession(body: body) }
    }
}
