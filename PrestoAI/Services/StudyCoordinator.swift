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
