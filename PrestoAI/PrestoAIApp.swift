import SwiftUI
import Combine

@main
struct PrestoAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar-only app — AppDelegate drives everything.
        // WindowGroup is required by SwiftUI; we immediately close it via onAppear.
        WindowGroup("Presto AI") {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear { NSApp.windows.forEach { $0.orderOut(nil) } }
        }
    }
}

// MARK: - Reusable Panel Factory

/// Creates a styled floating NSPanel matching Presto.AI's dark theme.
/// Eliminates duplicated window setup across all controllers.
func makePrestoPanel(size: NSSize, title: String = "") -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    panel.title = title
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.isMovableByWindowBackground = true
    panel.backgroundColor = Theme.nsBg(NSApp.effectiveAppearance)
    panel.isReleasedWhenClosed = false
    panel.center()
    panel.level = .floating
    return panel
}


class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusBarItem: NSStatusItem?
    private var overlayManager: OverlayManager?
    private var setupWindow: NSWindow?
    private var settingsPanel: NSPanel?
    
    // Dynamic menu items (updated in place instead of rebuilding the entire menu)
    private var queriesMenuItem: NSMenuItem?
    private var studyModeMenuItem: NSMenuItem?

    // Feedback controller
    private var feedbackController: FeedbackController?

    private var upgradePromptController: UpgradePromptController?
    private var paywallController: PaywallController?
    private var accountViewController: AccountViewController?
    private var checkoutViewController: CheckoutViewController?

    // Study Mode controllers
    private var studyOnboardingController: StudyOnboardingController?

    // Vision Click controller
    private let visionClickController = VisionClickController()
    private var automationController: AutomationController?

    // FIX #7: Observe state changes to keep menu updated
    private var stateObserver: NSObjectProtocol?
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nuke the default app main menu so macOS has nowhere to inject
        // "Settings..." with a gear icon (or any other auto-inserted items).
        NSApp.mainMenu = NSMenu()

        setupMenuBar()
        setupServices()

        // Listen for "Run Setup Again" from SettingsView (NotificationCenter avoids
        // fragile NSApp.delegate cast which fails under @NSApplicationDelegateAdaptor).
        NotificationCenter.default.addObserver(
            self, selector: #selector(rerunSetup),
            name: .rerunSetupWizard, object: nil
        )

        // Determine onboarding state and whether the wizard is needed
        let state = OnboardingState(rawValue: UserDefaults.standard.integer(forKey: "onboardingState")) ?? .notStarted
        let hasPermission = CGPreflightScreenCaptureAccess()

        if state == .completed && hasPermission {
            // Normal launch — menu bar only
            NSApp.setActivationPolicy(.accessory)
        } else if state == .completed && !hasPermission {
            // Permission was revoked after setup — reset and rerun wizard
            UserDefaults.standard.set(OnboardingState.notStarted.rawValue, forKey: "onboardingState")
            showSetupWizard()
        } else if state == .permissionRequested {
            // Back from quit & reopen
            showSetupWizard()
        } else {
            // state == .notStarted — fresh install
            showSetupWizard()
        }

        // FIX #7: Refresh menu when AppStateManager publishes changes
        // Use Combine or a simple polling approach since AppDelegate isn't a SwiftUI view
        setupStateObserver()

        print("[Presto.AI] App launched — Cmd+Shift+X to capture, Cmd+Shift+Z for quick prompt, Cmd+Shift+S for Study Mode, Cmd+Shift+D for accessibility scan, ESC to dismiss")
    }
    
    // FIX #7: Observe state changes from AppStateManager
    private func setupStateObserver() {
        // Use objectWillChange from ObservableObject to trigger menu refresh
        let cancellable = AppStateManager.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshMenuState()
            }
        }
        // Store in a property to keep alive
        objc_setAssociatedObject(self, "stateCancellable", cancellable, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    // MARK: - Setup Wizard
    
    private func showSetupWizard() {
        // Ensure app is visible in Dock before creating the window.
        NSApp.setActivationPolicy(.regular)

        // Determine how the wizard should start.
        let state = OnboardingState(rawValue: UserDefaults.standard.integer(forKey: "onboardingState")) ?? .notStarted
        let hasPermission = CGPreflightScreenCaptureAccess()

        let mode: WizardStartMode
        if state == .permissionRequested && hasPermission {
            mode = .resumeGranted
        } else if state == .permissionRequested {
            mode = .resumePending
        } else {
            mode = .fresh
        }

        var wizardView = SetupWizardView(onComplete: { [weak self] in
            DispatchQueue.main.async {
                self?.setupWindow?.orderOut(nil)
                self?.setupWindow?.contentView = nil
                self?.setupWindow = nil
                NSApp.setActivationPolicy(.accessory)
                print("[Presto.AI] Setup complete")
            }
        })
        wizardView.startMode = mode

        let hostingView = NSHostingView(rootView: wizardView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Presto.AI Setup"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.nsBg(NSApp.effectiveAppearance)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        }
        self.setupWindow = window
    }
    
    // MARK: - Menu Bar
    
    private func setupMenuBar() {
        if statusBarItem == nil {
            statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusBarItem?.button {
                button.image = makeMenuBarIcon()
            }
        }

        let menu = NSMenu()

        // Dynamic: queries remaining (shown for free users at top)
        let queriesItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        queriesItem.isEnabled = false
        queriesItem.isHidden = true
        menu.addItem(queriesItem)
        self.queriesMenuItem = queriesItem

        menu.addItem(NSMenuItem.separator())

        // Study Mode — Cmd+Shift+S (native right-aligned shortcut display)
        let studyItem = NSMenuItem(title: "Study Mode", action: #selector(toggleStudyMode), keyEquivalent: "s")
        studyItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(studyItem)
        self.studyModeMenuItem = studyItem

        // Capture Screenshot — Cmd+Shift+X
        let captureItem = NSMenuItem(title: "Capture Screenshot", action: #selector(captureScreenshot), keyEquivalent: "x")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(captureItem)

        // Quick Prompt — Cmd+Shift+Z
        let quickPromptItem = NSMenuItem(title: "Quick Prompt", action: #selector(quickPromptFromMenu), keyEquivalent: "z")
        quickPromptItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(quickPromptItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Refer 3 Friends — Get a Free Month", action: #selector(openReferral), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // "Settings" title triggers macOS auto-gear; use "Preferences" to avoid it.
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Feedback", action: #selector(openFeedback), keyEquivalent: ""))
        let quitItem = NSMenuItem(title: "Quit Presto AI", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        menu.delegate = self
        // Strip any auto-applied images synchronously before the menu is ever shown.
        menu.items.forEach { $0.image = nil }
        statusBarItem?.menu = menu

        // Set initial dynamic state
        refreshMenuState()
    }
    
    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.forEach { $0.image = nil }
        refreshMenuState()
    }

    /// Update dynamic menu items without rebuilding the whole menu.
    private func refreshMenuState() {
        let state = AppStateManager.shared

        switch state.currentState {
        case .freeActive:
            queriesMenuItem?.title = "\(state.queriesRemaining) free remaining"
            queriesMenuItem?.isHidden = false
        case .freeExhausted:
            queriesMenuItem?.title = "No free analyses remaining"
            queriesMenuItem?.isHidden = false
        case .referralActive:
            queriesMenuItem?.title = "Referral reward active"
            queriesMenuItem?.isHidden = false
        case .paid:
            queriesMenuItem?.isHidden = true
        case .anonymous:
            queriesMenuItem?.title = "Cannot connect to server"
            queriesMenuItem?.isHidden = false
        }

        // Update Study Mode menu item (key equivalent is set on the item itself)
        let studyMode = StudyModeManager.shared
        if studyMode.isActive {
            studyModeMenuItem?.title = "Study Mode (Active \(studyMode.sessionDurationText))"
        } else {
            studyModeMenuItem?.title = "Study Mode"
        }
        // Only enable for paid users
        studyModeMenuItem?.isEnabled = state.currentState == .paid || studyMode.isActive
    }
    
    // MARK: - Custom Menu Bar Icon
    
    private func makeMenuBarIcon() -> NSImage {
        let b64_1x = "iVBORw0KGgoAAAANSUhEUgAAABIAAAASCAYAAABWzo5XAAABVklEQVR4nJ3TvUpcURQF4G+cQUUIElAjCGl9i4AgJJIHCIi9rUWeIIGg8Qe1GoyKhkQiYmnUTtLmCSzE1tLCJhDU4uyrZ65zZXTDhXX32Wftn7UPnVktvsIaqHd4V1cH/qqYBwH1wGN4m1UxE7672EYF0TUmcBiXP6Abx/iGV3iHXhwptVnM4QXe4wxTeIn+iGliP/AaVgO3FFQQjWAR/7CJ0Tj/gb3Ac1FtT7SWC/HAPmW4ib+RYD7aKS5XktSi1J74/4ndwCf4E7gvb6lKvhuptZ3Ak/iCS7xBOKbxX8U+1bKDX/geeFZSrCEpeI4rfIzKa1Uku9gK/NX9TOoYwmdJvdfaKFa0uSepBQtBUk404F7Nu/Hk72gf64GXJInLMXkbLS11SVu7gZXwLeOgDUm75C02jAsMSjP5nSV5dNnKFZGexSm2n0OSl0oaYtn3ZMsX68kkt3KGMp9lvAfzAAAAAElFTkSuQmCC"
        let b64_2x = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADDElEQVR4nO2YX2jNYRjHP+dsNmwYMskWJeVqKVwQtyhXytxgI5IkIbVLS0vLny32J4mZsWb+XOxSKBnzJ4lbJSklWW6UC6bj4v2+/R6vsz+/82+Up06/8z7v732ez/u8f57nHPgvhZWEPmP1/zVSpGeSHIMlZNSKb9cAKwIAG7WSwE7exDtvAbqJoBOmrxEYBm4CM6ULJxZL/IwWA8sNSAJYIJAfQEpOFwWgKeClnk+AisBubJhSoBhoAPpxsytVXwlQCfQCA8B8YKrGtgqiR+29at/X+KyiBHAH+BzovNE1wHqjPyPnXWr7PdQt/bJg/ITEL8kGoBn4JmNXgFpgCb+fHP88q/cuBTB1wAgwBEwj5qnzJ+QI8EEOUsBPPb8C7bjlSeKWFKBN/ZcDmG3SvwLmBROILVOA1cBHGd0KlBmjfgO3q/+W2n4vbZf+BTBXuoz3j717rgJvTV+RgTkvpyPAe2CV9PXSPwfmmHFZSbGM1AOnBFhiDHfKaSuwDncFDAPH8gFjpVyG7TL5yHSa92qALwZmdi4h0olfwgty2qF2qZ6bge/AoIGpxKWWdOknKxAfmYuCaQtgdkj/DHcjJ3GHohZ3IfrLNOt8ZmfWJafnAhh/mp4SpQcvHbio5SQ6FqabaANbmDrpHwOzpKsAVgKHgU/q7wU2AdWZwlmYHhltCWB2GhibzeuBd/x5qaaAPtz+Gq+wSwuTAK7J0OkAZpf0j4giY4/2dGAt8EbvNQALJwpgJWk+vTJ2MoDZLf0Q6escO/smXLqxfbFgfHT65LRZfT4d7CGKzFhFl7/NN+JKlwTu1GUE0y+nJwIYX9fYDTzeBi0DqvR9wtGxpaeHaQpg9kk/GAMmI/HrXYzL1ingeACzX/qHwIyYMLFPk79BB+S0MYA5IP0DXE6LAxNbfIF1YxSYg0S1cJkZkzcYgKVyej2AOVRIGIiWqxx4jaubt6jvqGDu4S64vMN48U6qcRWhzzkp4G6hYUKoKlzpkAJu434dFBwmhErifn16mdR/LkbLRZMqOS0z/1n5BUqXpG40It4WAAAAAElFTkSuQmCC"
        
        let image = NSImage(size: NSSize(width: 18, height: 18))
        
        if let data1x = Data(base64Encoded: b64_1x),
           let rep1x = NSBitmapImageRep(data: data1x) {
            rep1x.pixelsWide = 18
            rep1x.pixelsHigh = 18
            rep1x.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep1x)
        }
        
        if let data2x = Data(base64Encoded: b64_2x),
           let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.pixelsWide = 36
            rep2x.pixelsHigh = 36
            rep2x.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep2x)
        }
        
        image.isTemplate = true
        return image
    }
    
    // MARK: - Services
    
    private func setupServices() {
        overlayManager = OverlayManager()
        studyOnboardingController = StudyOnboardingController()

        let hotkeys = HotkeyService.shared
        hotkeys.onCapture = { [weak self] in
            print("[Presto.AI] Hotkey triggered capture")
            self?.captureScreenshot()
        }
        hotkeys.onQuickPrompt = { [weak self] in
            print("[Presto.AI] Hotkey triggered quick prompt")
            self?.quickPromptCapture()
        }
        hotkeys.onEsc = { [weak self] in
            if let auto = self?.automationController, auto.isRunning {
                auto.cancel()
            } else {
                self?.overlayManager?.dismiss()
            }
        }
        hotkeys.onStudyModeToggle = { [weak self] in
            print("[Presto.AI] Hotkey triggered Study Mode toggle")
            self?.toggleStudyMode()
        }
        hotkeys.onAccessibilityScan = { [weak self] in
            print("[Presto.AI] Hotkey triggered vision click")
            self?.performVisionClick()
        }
        hotkeys.registerCapture()
        hotkeys.registerQuickPrompt()
        hotkeys.registerStudyMode()
        hotkeys.registerAccessibilityScan()

        // Wire Study Mode callbacks
        setupStudyModeCallbacks()
        setupAutoSolveCallbacks()
    }

    // MARK: - Study Mode

    private func setupStudyModeCallbacks() {
        let studyMode = StudyModeManager.shared

        studyMode.onNeedsOnboarding = { [weak self] in
            self?.studyOnboardingController?.show(
                onEnable: {
                    StudyModeManager.shared.activateAfterOnboarding()
                    self?.onStudyModeActivated()
                },
                onCustomize: {
                    // Open settings to Study Mode tab, then activate
                    self?.openStudyModeSettings()
                    StudyModeManager.shared.activateAfterOnboarding()
                    self?.onStudyModeActivated()
                }
            )
        }

        studyMode.onSuggestionAccepted = { [weak self] followUpPrompt in
            // Inject prompt into study bar and submit as if the user typed it
            self?.overlayManager?.injectPromptAndSubmit(followUpPrompt)
        }

        studyMode.onSessionEnded = { [weak self] summary in
            self?.overlayManager?.dismiss()
            // Show summary in popup overlay (same frosted glass style)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.overlayManager?.showStudySummary(text: summary)
            }
            self?.refreshMenuState()
        }

        // Wire suggestion accept/dismiss through overlay manager
        overlayManager?.onSuggestionAccept = {
            StudyModeManager.shared.acceptSuggestion()
        }
        overlayManager?.onSuggestionDismiss = {
            StudyModeManager.shared.dismissSuggestion()
        }

        // Observe suggestion changes
        let cancellable = studyMode.$currentSuggestion.sink { [weak self] suggestion in
            guard let suggestion = suggestion else { return }
            self?.overlayManager?.showStudySuggestion(text: suggestion.suggestionText)
        }
        objc_setAssociatedObject(self, "studySuggestionCancellable", cancellable, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    @objc private func toggleStudyMode() {
        let stateManager = AppStateManager.shared

        if stateManager.isOffline {
            overlayManager?.showError("Unable to connect to Presto AI servers. Check your internet connection and try again.")
            return
        }

        let studyMode = StudyModeManager.shared

        if studyMode.isActive {
            studyMode.deactivate()
        } else {
            // Check paid status
            if stateManager.currentState != .paid {
                showPaywall()
                return
            }
            studyMode.activate()
            if studyMode.isActive {
                onStudyModeActivated()
            }
        }
        refreshMenuState()
    }

    private func onStudyModeActivated() {
        // Show the Study Mode bar (persistent, compact, bottom-right)
        overlayManager?.onPromptSubmit = { [weak self] text in
            guard let self = self else { return }
            StudyModeManager.shared.recordQuestionAsked()

            // Expand the bar to show the answer area
            self.overlayManager?.expandStudyBar()

            // Capture screen and stream into the study bar
            Task {
                guard let screenshot = await self.captureForStudyMode() else { return }
                let contextPrefix = StudyModeManager.shared.buildSessionContextPrompt() ?? ""
                let fullPrompt = contextPrefix.isEmpty ? text : "\(contextPrefix)\n\nUser question: \(text)"

                let (compressed, mediaType) = ImageCompressor.compress(screenshot)
                let stateManager = AppStateManager.shared
                let deviceID = stateManager.deviceID
                let bodyDict: [String: Any] = [
                    "image": compressed,
                    "prompt": fullPrompt,
                    "media_type": mediaType,
                    "device_id": deviceID
                ]

                var isFirstChunk = true
                APIService.shared.sendScreenshot(screenshot, prompt: fullPrompt,
                    onChunk: { [weak self] chunk in
                        if isFirstChunk {
                            isFirstChunk = false
                        }
                        self?.overlayManager?.appendChunk(chunk)
                    },
                    onComplete: { [weak self] queriesRemaining, state in
                        Task { @MainActor in
                            self?.overlayManager?.signalStreamEnd()
                            stateManager.updateAfterQuery(queriesRemaining: queriesRemaining, state: state)
                        }
                    },
                    onError: { [weak self] error in
                        self?.overlayManager?.showError(error.localizedDescription)
                    }
                )
            }
        }
        overlayManager?.onStudyPauseToggle = {
            let sm = StudyModeManager.shared
            sm.isPaused ? sm.resume() : sm.pause()
        }
        overlayManager?.onStudyStop = { [weak self] in
            StudyModeManager.shared.deactivate()
        }
        overlayManager?.showPromptInput(studyMode: true)
        refreshMenuState()
    }

    private func captureForStudyMode() async -> String? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = CGWindowListCreateImage(
                    CGRect.null,
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

    private func openStudyModeSettings() {
        if let existing = settingsPanel, existing.isVisible {
            existing.orderOut(nil)
        }
        let panel = makePrestoPanel(size: NSSize(width: 420, height: 520), title: "Settings")
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: SettingsView(initialTab: .studyMode, onUpgrade: { [weak panel] in
            panel?.orderOut(nil)
            self.showAccountCreation()
        }))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsPanel = panel
    }
    
    // MARK: - Auto-Solve

    private func setupAutoSolveCallbacks() {
        AutoSolveManager.shared.onDeactivated = { [weak self] in
            self?.overlayManager?.updateAutoSolveButton(active: false)
        }

        overlayManager?.onAutoSolveToggle = { [weak self] in
            self?.toggleAutoSolve()
        }
    }

    private func toggleAutoSolve() {
        let stateManager = AppStateManager.shared

        if stateManager.isOffline {
            overlayManager?.showError("Unable to connect to Presto AI servers. Check your internet connection and try again.")
            return
        }

        let autoSolve = AutoSolveManager.shared

        if autoSolve.isActive {
            autoSolve.deactivate()
        } else {
            if stateManager.currentState != .paid {
                showPaywall()
                return
            }
            autoSolve.activate()
        }
    }

    // MARK: - Actions

    @objc private func captureScreenshot() {
        let stateManager = AppStateManager.shared

        if stateManager.isOffline {
            overlayManager?.showError("Unable to connect to Presto AI servers. Check your internet connection and try again.")
            return
        }

        if !stateManager.canAnalyze {
            showPaywall()
            return
        }
        
        Task {
            do {
                let screenshot = try await ScreenCaptureService.captureInteractive()
                await MainActor.run { self.overlayManager?.showLoading() }

                self.overlayManager?.storeConversationContext(screenshot: screenshot, initialPrompt: nil)

                var isFirstChunk = true
                APIService.shared.sendScreenshot(screenshot,
                    onChunk: { [weak self] chunk in
                        guard let self = self else { return }
                        if isFirstChunk {
                            isFirstChunk = false
                            self.overlayManager?.showResponse("")
                        }
                        self.overlayManager?.appendChunk(chunk)
                    },
                    onComplete: { [weak self] queriesRemaining, state in
                        Task { @MainActor in
                            self?.overlayManager?.signalStreamEnd()
                            stateManager.updateAfterQuery(queriesRemaining: queriesRemaining, state: state)
                            self?.refreshMenuState()
                            if state == "paid" && queriesRemaining > 0 && queriesRemaining <= 10 {
                                self?.overlayManager?.showUsageWarning(remaining: queriesRemaining)
                            }
                            // Wire follow-up for "Explain" captures (no initial prompt)
                            self?.wireFollowUp(screenshot: screenshot, lastQuestion: "Explain this screenshot")
                        }
                    },
                    onError: { [weak self] error in
                        if let apiError = error as? APIError, apiError == .noAccess {
                            Task { @MainActor in
                                self?.showPaywall()
                            }
                        } else {
                            self?.overlayManager?.showError(error.localizedDescription)
                        }
                    }
                )
            } catch {
                // Don't show error overlay for user-cancelled screenshots
                if let captureError = error as? CaptureError, captureError == .cancelled {
                    print("[Presto.AI] Screenshot cancelled by user")
                    return
                }
                await MainActor.run { self.overlayManager?.showError(error.localizedDescription) }
            }
        }
    }
    
    // MARK: - Vision Click (Cmd+Shift+D)

    private func performVisionClick() {
        // Capture the target app BEFORE showing overlay (which activates Presto AI)
        guard let targetApp = NSWorkspace.shared.frontmostApplication else { return }
        print("[VisionClick] Target app: \(targetApp.localizedName ?? "?") (PID \(targetApp.processIdentifier))")

        overlayManager?.onPromptSubmit = { [weak self] command in
            guard let self = self else { return }

            // Dismiss overlay BEFORE capturing screenshot so it's not in the image
            self.overlayManager?.dismiss()

            // Wait for overlay dismiss animation, then route through AutomationController
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                let controller = AutomationController()
                self.automationController = controller

                controller.handleCommand(command, targetApp: targetApp, overlayManager: self.overlayManager) { [weak self] in
                    self?.automationController = nil
                }
            }
        }
        overlayManager?.showPromptInput(placeholder: "What should I do?")
    }

    private func quickPromptCapture() {
        let stateManager = AppStateManager.shared

        if stateManager.isOffline {
            overlayManager?.showError("Unable to connect to Presto AI servers. Check your internet connection and try again.")
            return
        }

        if !stateManager.canAnalyze {
            showPaywall()
            return
        }

        Task {
            do {
                let screenshot = try await ScreenCaptureService.captureInteractive()
                await MainActor.run {
                    self.overlayManager?.onPromptSubmit = { [weak self] prompt in
                        self?.sendWithPrompt(screenshot: screenshot, prompt: prompt)
                    }
                    self.overlayManager?.showPromptInput()
                }
            } catch {
                if let captureError = error as? CaptureError, captureError == .cancelled {
                    print("[Presto.AI] Screenshot cancelled by user")
                    return
                }
                await MainActor.run { self.overlayManager?.showError(error.localizedDescription) }
            }
        }
    }

    private func sendWithPrompt(screenshot: String, prompt: String, isFollowUp: Bool = false) {
        let stateManager = AppStateManager.shared

        if !isFollowUp {
            overlayManager?.dismiss()
        }

        let startStreaming: () -> Void = { [weak self] in
            if !isFollowUp {
                self?.overlayManager?.storeConversationContext(screenshot: screenshot, initialPrompt: prompt)
                self?.overlayManager?.showLoading()
            }

            var isFirstChunk = true
            let actualPrompt = isFollowUp
                ? (self?.overlayManager?.buildContextPrompt(newQuestion: prompt) ?? prompt)
                : prompt

            APIService.shared.sendScreenshot(screenshot, prompt: actualPrompt,
                onChunk: { [weak self] chunk in
                    guard let self = self else { return }
                    if isFirstChunk {
                        isFirstChunk = false
                        if !isFollowUp {
                            self.overlayManager?.showResponse("")
                        }
                    }
                    self.overlayManager?.appendChunk(chunk)
                },
                onComplete: { [weak self] queriesRemaining, state in
                    Task { @MainActor in
                        self?.overlayManager?.signalStreamEnd()
                        stateManager.updateAfterQuery(queriesRemaining: queriesRemaining, state: state)
                        self?.refreshMenuState()
                        if state == "paid" && queriesRemaining > 0 && queriesRemaining <= 10 {
                            self?.overlayManager?.showUsageWarning(remaining: queriesRemaining)
                        }
                        self?.wireFollowUp(screenshot: screenshot, lastQuestion: prompt)
                    }
                },
                onError: { [weak self] error in
                    if let apiError = error as? APIError, apiError == .noAccess {
                        Task { @MainActor in
                            self?.showPaywall()
                        }
                    } else {
                        self?.overlayManager?.showError(error.localizedDescription)
                    }
                }
            )
        }

        if isFollowUp {
            startStreaming()
        } else {
            // Small delay to let dismiss complete before showing loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: startStreaming)
        }
    }

    private func wireFollowUp(screenshot: String, lastQuestion: String) {
        // Save the current turn's answer to history, then set up follow-up handler
        overlayManager?.addTurnToHistory(question: lastQuestion) { [weak self] in
            self?.overlayManager?.onFollowUpSubmit = { [weak self] followUpPrompt in
                guard let self = self else { return }
                let stateManager = AppStateManager.shared

                if !stateManager.canAnalyze {
                    self.showPaywall()
                    return
                }

                // Prepare UI for new turn
                self.overlayManager?.prepareFollowUp(question: followUpPrompt)

                // Send with conversation context
                self.sendWithPrompt(screenshot: screenshot, prompt: followUpPrompt, isFollowUp: true)
            }
        }
    }

    @objc private func openSettings() {
        if let existing = settingsPanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = makePrestoPanel(size: NSSize(width: 420, height: 420), title: "Settings")
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: SettingsView(initialTab: .settings, onUpgrade: { [weak panel] in
            panel?.orderOut(nil)
            self.showAccountCreation()
        }))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsPanel = panel
    }

    @objc private func signOut() {
        Task { @MainActor in
            AppStateManager.shared.signOut()
            refreshMenuState()
            
            let alert = NSAlert()
            alert.messageText = "Signed Out"
            alert.informativeText = "You've been signed out. Your free queries have been used."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    @objc private func openFeedback() {
        feedbackController = FeedbackController()
        feedbackController?.show()
    }

    @objc private func quickPromptFromMenu() {
        quickPromptCapture()
    }

    @objc private func openReferral() {
        showPaywall()
    }
    
    @objc func rerunSetup() {
        settingsPanel?.orderOut(nil)
        settingsPanel = nil
        setupWindow?.orderOut(nil)
        setupWindow?.contentView = nil
        setupWindow = nil
        UserDefaults.standard.set(OnboardingState.notStarted.rawValue, forKey: "onboardingState")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showSetupWizard()
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Auth Flow
    
    private func showUpgradePrompt() {
        upgradePromptController = UpgradePromptController()
        upgradePromptController?.show(
            onCreateAccount: { [weak self] in
                self?.showAccountCreation()
            },
            onPromoCode: { [weak self] in
                self?.showAccountCreation(openPromoField: true)
            },
            onDismiss: {
                print("[Presto.AI] Upgrade prompt dismissed")
            }
        )
    }

    private func showPaywall() {
        // Dismiss any existing paywall before showing a new one
        paywallController?.dismiss()
        paywallController = nil

        let deviceID = AppStateManager.shared.deviceID
        Task {
            do {
                let info = try await APIService.shared.getPaywallInfo(deviceID: deviceID)
                await MainActor.run {
                    paywallController = PaywallController()
                    paywallController?.show(info: info) { [weak self] in
                        // onSubscribe — go through existing account creation + checkout flow
                        self?.showAccountCreation()
                    }
                }
            } catch {
                // Fallback to legacy upgrade prompt if paywall endpoint fails
                await MainActor.run {
                    showUpgradePrompt()
                }
            }
        }
    }
    
    private func showAccountCreation(openPromoField: Bool = false) {
        accountViewController = AccountViewController()
        accountViewController?.show(openPromoField: openPromoField) { [weak self] jwt in
            self?.handlePostLogin(jwt: jwt)
        }
    }

    private func handlePostLogin(jwt: String) {
        Task {
            AppStateManager.shared.saveJWT(jwt)
            do {
                let profile = try await APIService.shared.getProfile()
                if profile.subscriptionStatus == "active" {
                    await MainActor.run {
                        AppStateManager.shared.setStateToPaid(jwt: jwt)
                        self.refreshMenuState()
                        self.showSuccessMessage()
                    }
                } else {
                    showCheckout(jwt: jwt)
                }
            } catch {
                showCheckout(jwt: jwt)
            }
        }
    }
    
    // FIX #5: Don't save JWT until payment is confirmed
    private func showCheckout(jwt: String) {
        Task {
            do {
                // Temporarily save JWT to make the profile request,
                // but track that payment hasn't completed yet
                AppStateManager.shared.saveJWT(jwt)
                
                let profile = try await APIService.shared.getProfile()
                let deviceID = AppStateManager.shared.deviceID
                let checkoutURL = try await APIService.shared.getCheckoutURL(email: profile.email, deviceID: deviceID)
                
                await MainActor.run {
                    checkoutViewController = CheckoutViewController()
                    checkoutViewController?.show(checkoutURL: checkoutURL) { [weak self] finalJWT in
                        Task { @MainActor in
                            AppStateManager.shared.setStateToPaid(jwt: finalJWT)
                            self?.refreshMenuState()
                            self?.showSuccessMessage()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    // FIX #5: Clear the pre-emptively saved JWT on checkout failure
                    // The user registered but didn't pay — reset to device state
                    Task {
                        await AppStateManager.shared.initializeState()
                    }
                    
                    let alert = NSAlert()
                    alert.messageText = "Checkout Error"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    private func showSuccessMessage() {
        let alert = NSAlert()
        alert.messageText = "You're all set!"
        alert.informativeText = "Press Cmd+Shift+X to continue."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
