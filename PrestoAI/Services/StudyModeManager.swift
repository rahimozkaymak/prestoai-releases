import Foundation
import AppKit
import CoreGraphics
import Combine

// MARK: - Study Mode Session

struct StudySession {
    let id: String
    let startedAt: Date
    var capturesCount: Int = 0
    var suggestionsShown: Int = 0
    var suggestionsAccepted: Int = 0
    var questionsAsked: Int = 0
    var appsVisited: Set<String> = []
    var recentWindowTitles: [String] = []
    var previousSuggestions: [String] = []
}

// MARK: - Study Capture Decision

struct CaptureDecision {
    var lastCaptureTime: Date = .distantPast
    var lastWindowTitle: String = ""
    var lastAppName: String = ""
    var userIsActivelyTyping: Bool = false

    mutating func shouldCapture(currentWindow: String, currentApp: String, interval: TimeInterval) -> Bool {
        // Always capture on window/app change
        if currentWindow != lastWindowTitle || currentApp != lastAppName {
            return true
        }
        // Capture on timer if >interval since last capture
        if Date().timeIntervalSince(lastCaptureTime) > interval {
            return true
        }
        // Don't capture if user is typing
        if userIsActivelyTyping {
            return false
        }
        return false
    }

    mutating func recordCapture(window: String, app: String) {
        lastCaptureTime = Date()
        lastWindowTitle = window
        lastAppName = app
    }
}

// MARK: - Study Suggestion

struct StudySuggestion {
    let captureId: String
    let suggestionText: String
    let suggestionType: String
    let confidence: String
    let followUpPrompt: String
}

// MARK: - Privacy Exclusions

struct PrivacyFilter {
    static let defaultExcludedApps: Set<String> = [
        "1Password", "Keychain Access", "System Preferences", "System Settings",
        "Messages", "Signal", "WhatsApp", "Telegram",
        "LastPass", "Bitwarden", "Dashlane"
    ]

    static let excludedWindowTitleKeywords: [String] = [
        "Private Browsing", "Incognito",
        "password", "login", "sign in", "bank",
        "Password", "Login", "Sign In", "Bank"
    ]

    static func isExcluded(appName: String, windowTitle: String, userExclusions: Set<String>) -> Bool {
        let allExcluded = defaultExcludedApps.union(userExclusions)
        if allExcluded.contains(appName) {
            return true
        }
        let titleLower = windowTitle.lowercased()
        for keyword in excludedWindowTitleKeywords {
            if titleLower.contains(keyword.lowercased()) {
                return true
            }
        }
        return false
    }
}

// MARK: - Study Mode Manager

class StudyModeManager: ObservableObject {
    static let shared = StudyModeManager()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var currentSuggestion: StudySuggestion?
    @Published private(set) var sessionDurationText: String = ""
    @Published private(set) var currentActivity: String = ""
    @Published private(set) var isPrivateAppDetected: Bool = false

    private var session: StudySession?
    private var captureDecision = CaptureDecision()
    private var captureTimer: Timer?
    private var durationTimer: Timer?
    private var typingTimer: Timer?
    private var keyEventMonitor: Any?
    private var appObserver: NSObjectProtocol?

    // Notification anti-spam
    private var lastNotificationTime: Date = .distantPast
    private var consecutiveDismissals: Int = 0

    // Request guard
    private var isRequestInFlight = false

    // Settings (from UserDefaults)
    var captureInterval: TimeInterval {
        let val = UserDefaults.standard.double(forKey: "studyModeCaptureInterval")
        return val > 0 ? val : 45
    }
    var suggestionMinInterval: TimeInterval {
        let val = UserDefaults.standard.double(forKey: "studyModeSuggestionInterval")
        return val > 0 ? val : 60
    }
    var userExcludedApps: Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: "studyModeExcludedApps") ?? []
        return Set(arr)
    }

    private var hasShownOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "studyModeOnboardingShown") }
        set { UserDefaults.standard.set(newValue, forKey: "studyModeOnboardingShown") }
    }

    // Callbacks
    var onSuggestionAccepted: ((String) -> Void)?
    var onNeedsOnboarding: (() -> Void)?
    var onSessionEnded: ((String) -> Void)?

    private init() {}

    // MARK: - Toggle

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    func activate() {
        let stateManager = AppStateManager.shared

        // Study Mode is paid-only (or trial)
        guard stateManager.currentState == .paid else {
            return
        }

        // Show onboarding first time
        if !hasShownOnboarding {
            onNeedsOnboarding?()
            return
        }

        startSession()
    }

    /// Called after onboarding is accepted
    func activateAfterOnboarding() {
        hasShownOnboarding = true
        startSession()
    }

    func deactivate() {
        guard isActive else { return }

        let summary = buildSessionSummary()

        // Stop everything
        captureTimer?.invalidate()
        captureTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        typingTimer?.invalidate()
        typingTimer = nil

        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        if let obs = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appObserver = nil
        }

        // Report session to backend
        if let session = session {
            reportSessionEnd(session: session)
        }

        session = nil
        captureDecision = CaptureDecision()
        isActive = false
        isPaused = false
        currentSuggestion = nil
        isPrivateAppDetected = false
        sessionDurationText = ""
        currentActivity = ""
        consecutiveDismissals = 0

        onSessionEnded?(summary)

        print("[StudyMode] Deactivated")
    }

    func pause() {
        isPaused = true
        captureTimer?.invalidate()
        captureTimer = nil
        print("[StudyMode] Paused")
    }

    func resume() {
        isPaused = false
        startCaptureTimer()
        print("[StudyMode] Resumed")
    }

    // MARK: - Session Lifecycle

    private func startSession() {
        let newSession = StudySession(
            id: UUID().uuidString,
            startedAt: Date()
        )
        session = newSession
        isActive = true
        isPaused = false
        consecutiveDismissals = 0

        // Start observing app switches
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleAppSwitch(appName: app.localizedName ?? "Unknown")
        }

        // Start typing detection
        keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.captureDecision.userIsActivelyTyping = true
            self?.typingTimer?.invalidate()
            self?.typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                self?.captureDecision.userIsActivelyTyping = false
            }
        }

        // Start capture timer
        startCaptureTimer()

        // Start duration display timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateDurationText()
        }
        updateDurationText()

        // First capture after 3-second delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.performCapture()
        }

        print("[StudyMode] Activated — session \(newSession.id)")
    }

    private func startCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            self?.checkAndCapture()
        }
    }

    // MARK: - Capture Pipeline

    private func handleAppSwitch(appName: String) {
        guard isActive, !isPaused else { return }

        session?.appsVisited.insert(appName)

        // Check privacy
        let windowTitle = getCurrentWindowTitle()
        if PrivacyFilter.isExcluded(appName: appName, windowTitle: windowTitle, userExclusions: userExcludedApps) {
            isPrivateAppDetected = true
            print("[StudyMode] Private app detected: \(appName)")
            return
        }
        isPrivateAppDetected = false

        // Capture on app switch
        performCapture()
    }

    private func checkAndCapture() {
        guard isActive, !isPaused, !isPrivateAppDetected else { return }

        let appName = getCurrentAppName()
        let windowTitle = getCurrentWindowTitle()

        if PrivacyFilter.isExcluded(appName: appName, windowTitle: windowTitle, userExclusions: userExcludedApps) {
            isPrivateAppDetected = true
            return
        }
        isPrivateAppDetected = false

        if captureDecision.shouldCapture(currentWindow: windowTitle, currentApp: appName, interval: captureInterval) {
            performCapture()
        }
    }

    private func performCapture() {
        guard isActive, !isPaused, !isPrivateAppDetected else { return }

        let appName = getCurrentAppName()
        let windowTitle = getCurrentWindowTitle()

        // Double-check privacy before capturing
        if PrivacyFilter.isExcluded(appName: appName, windowTitle: windowTitle, userExclusions: userExcludedApps) {
            isPrivateAppDetected = true
            return
        }

        captureDecision.recordCapture(window: windowTitle, app: appName)

        Task {
            guard let imageBase64 = await captureScreen() else { return }

            // Compress for analysis (lower quality than interactive captures)
            let (compressed, mediaType) = ImageCompressor.compressForStudy(imageBase64)

            await MainActor.run {
                session?.capturesCount += 1
                session?.appsVisited.insert(appName)
                if session?.recentWindowTitles.count ?? 0 > 10 {
                    session?.recentWindowTitles.removeFirst()
                }
                session?.recentWindowTitles.append(windowTitle)
                currentActivity = windowTitle
            }

            // Send to backend for analysis
            await analyzeCapture(
                imageBase64: compressed,
                mediaType: mediaType,
                appName: appName,
                windowTitle: windowTitle
            )
        }
    }

    private func captureScreen() async -> String? {
        // Use CGWindowListCreateImage for silent capture (no user interaction)
        guard CGPreflightScreenCaptureAccess() else {
            print("[StudyMode] No screen recording permission")
            return nil
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let cgImage = CGWindowListCreateImage(
                    CGRect.null,  // Full screen
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.bestResolution]
                ) else {
                    continuation.resume(returning: nil)
                    return
                }

                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: pngData.base64EncodedString())
            }
        }
    }

    // MARK: - Analysis

    private func analyzeCapture(imageBase64: String, mediaType: String, appName: String, windowTitle: String) async {
        guard let session = session, !isRequestInFlight else { return }
        isRequestInFlight = true

        let captureId = UUID().uuidString
        let clipboardText = await MainActor.run { NSPasteboard.general.string(forType: .string) ?? "" }

        let context: [String: Any] = [
            "session_id": session.id,
            "capture_id": captureId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "app_name": appName,
            "window_title": windowTitle,
            "clipboard_text": String(clipboardText.prefix(500)),
            "image": imageBase64,
            "media_type": mediaType,
            "device_id": AppStateManager.shared.deviceID,
            "session_context": [
                "duration_minutes": Int(Date().timeIntervalSince(session.startedAt) / 60),
                "apps_visited": Array(session.appsVisited),
                "previous_suggestions": Array(session.previousSuggestions.suffix(5)),
                "questions_asked": session.questionsAsked
            ] as [String: Any]
        ]

        do {
            let suggestion = try await APIService.shared.analyzeStudyCapture(context: context)
            isRequestInFlight = false

            if let suggestion = suggestion {
                await MainActor.run {
                    self.handleSuggestion(suggestion)
                }
            }
        } catch {
            isRequestInFlight = false
            print("[StudyMode] Analysis error: \(error.localizedDescription)")
        }
    }

    private func handleSuggestion(_ suggestion: StudySuggestion) {
        guard isActive else { return }

        // Anti-spam: check timing
        let effectiveInterval = consecutiveDismissals >= 3 ? 120.0 : suggestionMinInterval
        guard Date().timeIntervalSince(lastNotificationTime) >= effectiveInterval else {
            return
        }

        session?.suggestionsShown += 1
        session?.previousSuggestions.append(suggestion.suggestionText)
        lastNotificationTime = Date()

        currentSuggestion = suggestion
    }

    // MARK: - Suggestion Actions

    func acceptSuggestion() {
        guard let suggestion = currentSuggestion else { return }
        session?.suggestionsAccepted += 1
        consecutiveDismissals = 0
        currentSuggestion = nil
        onSuggestionAccepted?(suggestion.followUpPrompt)
    }

    func dismissSuggestion() {
        consecutiveDismissals += 1
        currentSuggestion = nil
    }

    func recordQuestionAsked() {
        session?.questionsAsked += 1
    }

    // MARK: - Context for Prompt Box

    func buildSessionContextPrompt() -> String? {
        guard let session = session else { return nil }
        let duration = Int(Date().timeIntervalSince(session.startedAt) / 60)
        let apps = session.appsVisited.joined(separator: ", ")
        let windows = session.recentWindowTitles.suffix(5).joined(separator: "; ")

        return """
        The user has Study Mode enabled and has been working for \(duration) minutes.
        Apps used: \(apps)
        Recent windows: \(windows)
        Suggestions shown: \(session.suggestionsShown), accepted: \(session.suggestionsAccepted)
        """
    }

    // MARK: - Helpers

    private func getCurrentAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    private func getCurrentWindowTitle() -> String {
        // Get the frontmost window title via accessibility or CGWindow
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return ""
        }

        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0

        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  pid == frontPID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }
            return window[kCGWindowName as String] as? String ?? ""
        }
        return ""
    }

    private func updateDurationText() {
        guard let session = session else { return }
        let minutes = Int(Date().timeIntervalSince(session.startedAt) / 60)
        if minutes < 1 {
            sessionDurationText = "Just started"
        } else if minutes < 60 {
            sessionDurationText = "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            sessionDurationText = "\(hours)h \(mins)m"
        }
    }

    private func buildSessionSummary() -> String {
        guard let session = session else { return "" }
        let duration = Int(Date().timeIntervalSince(session.startedAt) / 60)
        let tasks = session.suggestionsAccepted
        return "\(duration)min session, helped with \(tasks) task\(tasks == 1 ? "" : "s")"
    }

    private func reportSessionEnd(session: StudySession) {
        let duration = Int(Date().timeIntervalSince(session.startedAt))
        let body: [String: Any] = [
            "session_id": session.id,
            "device_id": AppStateManager.shared.deviceID,
            "duration_seconds": duration,
            "captures_count": session.capturesCount,
            "suggestions_shown": session.suggestionsShown,
            "suggestions_accepted": session.suggestionsAccepted,
            "questions_asked": session.questionsAsked
        ]

        Task {
            try? await APIService.shared.reportStudySession(body: body)
        }
    }
}

// MARK: - ImageCompressor Extension for Study Mode

extension ImageCompressor {
    /// Lower quality compression for study mode analysis (not user-facing)
    static func compressForStudy(_ base64: String) -> (String, String) {
        guard let data = Data(base64Encoded: base64),
              let nsImage = NSImage(data: data) else {
            return (base64, "image/png")
        }

        // Resize to 1024px max, JPEG at 60% quality (analysis-only, per spec)
        if let result = resizeAndEncodeStudy(nsImage, maxSide: 1024, quality: 0.60) {
            return (result, "image/jpeg")
        }
        return (base64, "image/png")
    }

    private static func resizeAndEncodeStudy(_ image: NSImage, maxSide: CGFloat, quality: CGFloat) -> String? {
        var size = image.size
        if size.width > maxSide || size.height > maxSide {
            let scale = maxSide / max(size.width, size.height)
            size = NSSize(width: size.width * scale, height: size.height * scale)
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let resizedCG = ctx.makeImage() else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: resizedCG)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else { return nil }

        return jpeg.base64EncodedString()
    }
}
