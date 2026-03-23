import AppKit
import Foundation

/// Agent-style automation: observe → think → act → repeat.
/// Haiku navigates. Sonnet solves problems and generates plans.
/// Homework mode bypasses the agent loop — one Sonnet call solves everything.
class AutomationController {

    private let visionClickController = VisionClickController()
    private let haikuModel = "claude-haiku-4-5-20251001"
    private let sonnetModel = "claude-sonnet-4-6"
    private let statusBar = AutomationStatusBar()

    private(set) var isCancelled = false
    private(set) var isRunning = false

    private var targetApp: NSRunningApplication?
    private var completion: (() -> Void)?
    private var goal: String = ""
    private var actionHistory: [String] = []
    private var iteration = 0
    private let maxIterations = 30  // reduced from 50 — plans make it more efficient
    private var consecutiveErrors = 0
    private var consecutiveWaits = 0

    /// Answers from Sonnet solve — Haiku uses these when typing
    private var solvedAnswers: String = ""

    /// App/website skill loaded for this session
    private var currentSkill: String = ""

    // MARK: - Frame Diff (Step 1)
    private var previousScreenshot: NSImage?
    private var lastFrameDiff: Double = 0.0

    // MARK: - Retry Budget (Step 4)
    private var lastClickCenter: CGPoint?
    private var sameTargetClicks = 0

    // MARK: - Plan-Then-Act (Step 6)
    private var plan: [String] = []
    private var currentPlanStep = 0
    private var actionsOnCurrentStep = 0

    // MARK: - App Bounds (Step 9)
    private var outsideAppClickCount = 0
    private var lastBoundsBlockReason: String = ""

    // MARK: - Dangerous Patterns (Step 10)
    private let dangerousPatterns = [
        "send", "submit", "purchase", "buy", "pay", "delete",
        "password", "sign out", "log out", "remove", "unsubscribe"
    ]

    // MARK: - Entry Point

    func handleCommand(_ command: String, targetApp: NSRunningApplication, overlayManager: OverlayManager?, onDone: @escaping () -> Void) {
        self.targetApp = targetApp
        self.completion = onDone
        self.goal = command
        self.isCancelled = false
        self.isRunning = true
        self.iteration = 0
        self.actionHistory = []
        self.consecutiveErrors = 0
        self.consecutiveWaits = 0
        self.solvedAnswers = ""
        self.currentSkill = ""
        self.previousScreenshot = nil
        self.lastFrameDiff = 0.0
        self.lastClickCenter = nil
        self.sameTargetClicks = 0
        self.plan = []
        self.currentPlanStep = 0
        self.actionsOnCurrentStep = 0
        self.outsideAppClickCount = 0
        self.lastBoundsBlockReason = ""

        print("[Agent] Goal: \(command)")

        statusBar.show(task: command)
        HotkeyService.shared.registerEsc()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadSkillAndStart(command: command)
        }
    }

    func cancel() {
        guard isRunning else { return }
        print("[Agent] Cancelled by ESC")
        isCancelled = true
        isRunning = false
        statusBar.update("Cancelled")
        HotkeyService.shared.unregisterEsc()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.statusBar.dismiss()
            self?.completion?()
            self?.completion = nil
        }
    }

    private func finish(_ status: String, delay: TimeInterval = 0.5) {
        isRunning = false
        print("[Agent] \(status)")
        statusBar.update(status)
        HotkeyService.shared.unregisterEsc()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.statusBar.dismiss()
            self?.completion?()
            self?.completion = nil
        }
    }

    // MARK: - Skill Loading

    private func loadSkillAndStart(command: String) {
        guard !isCancelled, isRunning, let targetApp = targetApp else { return }

        guard let scan = visionClickController.scanScreen(targetApp: targetApp) else {
            startMode(command: command)
            return
        }

        let ocrText = scan.elements.filter { $0.source == "ocr" }.map { $0.label }

        if let skill = AppSkills.shared.getSkill(for: targetApp, ocrText: ocrText) {
            currentSkill = skill
            print("[Agent] Loaded skill: \(skill.prefix(60))...")
            statusBar.update("Skill loaded")
            startMode(command: command)
            return
        }

        let bundleID = targetApp.bundleIdentifier ?? ""
        let isBrowser = ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox",
                         "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser"]
            .contains(bundleID)

        if isBrowser, let websiteName = AppSkills.shared.detectWebsiteName(from: ocrText) {
            guard let base64 = visionClickController.imageToBase64JPEG(scan.image) else {
                startMode(command: command)
                return
            }
            let elementList = visionClickController.buildElementList(elements: scan.elements)
            statusBar.update("Learning \(websiteName)...")

            AppSkills.shared.generateWebsiteSkill(websiteKey: websiteName, base64Screenshot: base64, elementList: elementList) { [weak self] skill in
                if let skill = skill { self?.currentSkill = skill }
                self?.startMode(command: command)
            }
            return
        }

        if !isBrowser {
            guard let base64 = visionClickController.imageToBase64JPEG(scan.image) else {
                startMode(command: command)
                return
            }
            let elementList = visionClickController.buildElementList(elements: scan.elements)
            let appName = targetApp.localizedName ?? "app"
            statusBar.update("Learning \(appName)...")

            AppSkills.shared.generateSkill(for: targetApp, base64Screenshot: base64, elementList: elementList) { [weak self] skill in
                if let skill = skill { self?.currentSkill = skill }
                self?.startMode(command: command)
            }
            return
        }

        startMode(command: command)
    }

    private func startMode(command: String) {
        guard !isCancelled, isRunning else { return }
        if isHomeworkCommand(command) {
            print("[Agent] Homework mode activated")
            homeworkMode()
        } else {
            // Generate a plan before starting navigation
            generatePlan()
        }
    }

    // MARK: - Plan-Then-Act (Step 6)

    private func generatePlan() {
        guard !isCancelled, isRunning, let targetApp = targetApp else { agentLoop(); return }

        statusBar.update("Planning...")

        guard let scan = visionClickController.scanScreen(targetApp: targetApp),
              let base64 = visionClickController.imageToBase64JPEG(scan.image) else {
            agentLoop()
            return
        }

        let elementList = visionClickController.buildElementList(elements: scan.elements)
        let skillContext = currentSkill.isEmpty ? "" : "\n\(currentSkill)\n"

        let prompt = """
        GOAL: \(goal)
        APP: \(targetApp.localizedName ?? "unknown")
        \(skillContext)
        SCREEN ELEMENTS (first 2000 chars):
        \(String(elementList.prefix(2000)))

        Create a 3-6 step plan to achieve this goal. Each step should be a single user-visible action (click, type, scroll, etc.).
        Return ONLY a JSON array of strings. No markdown, no explanation.
        Example: ["Click Spotify in dock", "Click search bar", "Type song name and press Enter", "Click the song in results", "Verify music is playing"]
        """

        callClaude(base64Image: base64, prompt: prompt, model: sonnetModel) { [weak self] response in
            guard let self = self, !self.isCancelled, self.isRunning else { return }

            // Parse plan
            let cleaned = self.stripMarkdownFences(response)
            if let start = cleaned.firstIndex(of: "["),
               let end = cleaned.lastIndex(of: "]"),
               let data = String(cleaned[start...end]).data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                self.plan = arr
                self.currentPlanStep = 0
                self.actionsOnCurrentStep = 0
                print("[Agent] Plan: \(arr)")
            } else {
                print("[Agent] Plan generation failed, proceeding without plan")
            }

            // Store initial screenshot for frame diff
            self.previousScreenshot = scan.image

            self.agentLoop()
        }
    }

    private func planContext() -> String {
        guard !plan.isEmpty else { return "" }

        var planStr = "\nPLAN:\n"
        for (i, step) in plan.enumerated() {
            let prefix: String
            if i < currentPlanStep {
                prefix = "[x]"
            } else if i == currentPlanStep {
                prefix = ">>>"
            } else {
                prefix = "[ ]"
            }
            planStr += "  \(i + 1). \(prefix) \(step)\n"
        }
        if currentPlanStep < plan.count {
            planStr += "CURRENT STEP: \(currentPlanStep + 1) — \(plan[currentPlanStep])\n"
        }
        return planStr
    }

    // MARK: - Homework Mode Routing

    private func isHomeworkCommand(_ command: String) -> Bool {
        let homeworkKeywords = [
            "solve", "answer", "homework", "fill in", "complete this",
            "do this assignment", "do this", "solve this", "answer this",
            "do my homework", "fill this out", "do these questions",
            "do these", "answer these", "solve these"
        ]
        let lower = command.lowercased()
        return homeworkKeywords.contains(where: { lower.contains($0) })
    }

    // MARK: - Homework Mode

    private func homeworkMode() {
        guard !isCancelled, isRunning else { return }
        homeworkCycle(scrollCycles: 0, maxScrollCycles: 5)
    }

    private func homeworkCycle(scrollCycles: Int, maxScrollCycles: Int) {
        guard !isCancelled, isRunning else { return }
        guard scrollCycles < maxScrollCycles else {
            finish("Done!")
            return
        }

        print("[Agent] Scanning page...")
        statusBar.update("Scanning...")

        ensureFocus()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, !self.isCancelled, self.isRunning else { return }

            guard let targetApp = self.targetApp,
                  let scan = self.visionClickController.scanScreen(targetApp: targetApp),
                  let base64 = self.visionClickController.imageToBase64JPEG(scan.image) else {
                self.finish("Screen capture failed")
                return
            }

            let hasAnswerFields = scan.elements.contains { el in
                el.source == "box" || el.source == "synth" ||
                el.label.contains("Empty answer box") ||
                (el.label.contains("Input [") && el.source == "ax")
            }

            if !hasAnswerFields && scrollCycles > 0 {
                self.finish("Done!")
                return
            }

            if !hasAnswerFields && scrollCycles == 0 {
                print("[Agent] No answer fields found, falling back to navigation mode")
                let elementList = self.visionClickController.buildElementList(elements: scan.elements)
                self.think(base64: base64, elementList: elementList, elements: scan.elements)
                return
            }

            let elementList = self.visionClickController.buildElementList(elements: scan.elements)
            print("[Agent] Solving...")
            self.statusBar.update("Solving...")

            self.solveHomework(base64: base64, elementList: elementList, elements: scan.elements) { [weak self] actions in
                guard let self = self, !self.isCancelled, self.isRunning else { return }

                if let actions = actions, !actions.isEmpty {
                    print("[Agent] Filling \(actions.count) answers...")
                    self.statusBar.update("Filling \(actions.count) answers...")
                    self.executeHomeworkActions(actions, elements: scan.elements) {
                        guard !self.isCancelled, self.isRunning else { return }
                        print("[Agent] Scrolling for more...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.ensureFocus()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                ClickExecutor.scroll(direction: "down")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    ClickExecutor.scroll(direction: "down")
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        self.homeworkCycle(scrollCycles: scrollCycles + 1, maxScrollCycles: maxScrollCycles)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        ClickExecutor.scroll(direction: "down")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            ClickExecutor.scroll(direction: "down")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.homeworkCycle(scrollCycles: scrollCycles + 1, maxScrollCycles: maxScrollCycles)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Homework Solve

    private struct HomeworkAction {
        let element: Int
        let answer: String
        let type: String
        let clearFirst: Bool
    }

    private func solveHomework(base64: String, elementList: String, elements: [VisionClickController.ScreenElement], completion: @escaping ([HomeworkAction]?) -> Void) {
        let skillContext = currentSkill.isEmpty ? "" : "\n\(currentSkill)\n"
        let prompt = """
        You are looking at a screenshot of a homework or quiz page. Your job is to:
        \(skillContext)

        1. READ the full question carefully. Understand what is being asked — the math, the physics, the concept.

        2. IDENTIFY every answer field on the screen. These are:
           - Elements labeled "Empty answer box" — white rectangles near labels like "R =", "I ="
           - Elements labeled "Input box for X" — synthesized input fields
           - Input fields labeled "Input [TextField]" — text fields detected by accessibility
           - Checkboxes (small squares next to statements — check the correct ones)
           - Radio buttons (small circles next to options — select the correct one)
           - Text inputs that already have a wrong answer (may show a red X) — these need correcting

        3. SOLVE the problem completely. Show no work — just determine the final answers.

        4. MAP each answer to the correct element from the element list below.

        Return ONLY a JSON array. Each entry:
        {"element": <element number>, "answer": "<what to type or select>", "type": "type", "clear_first": false}

        Rules:
        - "element" is the number in brackets [N] from the element list.
        - For text inputs: "type" is the action type, "answer" is the text to type. Set "clear_first": true if the field already has a wrong value.
        - For checkboxes: use type "check" to check, "uncheck" to uncheck.
        - For radio buttons: use type "radio". Only include the correct option.
        - For dropdowns: use type "select", "answer" is the option to choose.
        - For interval notation: use standard math formatting like (-1, 1) or [-3, 5) or (-inf, inf).
        - For numeric answers: just the number. No units unless the field expects them.
        - For "does not exist": type "DNE".
        - Order the array top-to-bottom as they appear on the page.
        - Return ONLY the JSON array — no markdown, no explanation, no other text.

        ELEMENT LIST:
        \(elementList)
        """

        callClaude(base64Image: base64, prompt: prompt, model: sonnetModel) { [weak self] response in
            guard let self = self else { completion(nil); return }

            print("[Agent] Homework solve response: \(response.prefix(500))")

            if let actions = self.parseHomeworkActions(from: response) {
                completion(actions)
            } else {
                print("[Agent] Failed to parse homework JSON, retrying...")
                self.retryHomeworkParse(originalResponse: response, completion: completion)
            }
        }
    }

    private func retryHomeworkParse(originalResponse: String, completion: @escaping ([HomeworkAction]?) -> Void) {
        let prompt = """
        The following text was supposed to be a JSON array but couldn't be parsed.
        Fix it and return ONLY a valid JSON array. No explanation.

        \(originalResponse.prefix(2000))
        """

        callClaude(base64Image: "", prompt: prompt, model: sonnetModel) { [weak self] response in
            if let actions = self?.parseHomeworkActions(from: response) {
                completion(actions)
            } else {
                print("[Agent] Retry parse also failed")
                completion(nil)
            }
        }
    }

    private func parseHomeworkActions(from text: String) -> [HomeworkAction]? {
        let cleaned = stripMarkdownFences(text)
        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]") else { return nil }

        let jsonStr = String(cleaned[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        var actions: [HomeworkAction] = []
        for dict in array {
            guard let element = dict["element"] as? Int,
                  let answer = (dict["answer"] as? String) ?? (dict["answer"] as? NSNumber).map({ String(describing: $0) }),
                  let type = dict["type"] as? String else { continue }

            let clearFirst = dict["clear_first"] as? Bool ?? false
            actions.append(HomeworkAction(element: element, answer: answer, type: type, clearFirst: clearFirst))
        }

        return actions.isEmpty ? nil : actions
    }

    // MARK: - Homework Execution

    private func executeHomeworkActions(_ actions: [HomeworkAction], elements: [VisionClickController.ScreenElement], onDone: @escaping () -> Void) {
        executeNextAction(actions: actions, index: 0, elements: elements, onDone: onDone)
    }

    private func executeNextAction(actions: [HomeworkAction], index: Int, elements: [VisionClickController.ScreenElement], onDone: @escaping () -> Void) {
        guard !isCancelled, isRunning else { return }
        guard index < actions.count else { onDone(); return }

        let action = actions[index]
        let elIdx = action.element - 1
        guard elIdx >= 0, elIdx < elements.count else {
            executeNextAction(actions: actions, index: index + 1, elements: elements, onDone: onDone)
            return
        }

        let el = elements[elIdx]
        print("[Agent] [\(index + 1)/\(actions.count)] \(el.label.prefix(40))")
        statusBar.update("[\(index + 1)/\(actions.count)] Filling...")

        ensureFocus()

        switch action.type {
        case "type":
            if action.clearFirst {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    ClickExecutor.click(at: el.center)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        ClickExecutor.pressKey("cmd+a")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            ClickExecutor.typeText(action.answer)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                self.executeNextAction(actions: actions, index: index + 1, elements: elements, onDone: onDone)
                            }
                        }
                    }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    ClickExecutor.click(at: el.center)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        ClickExecutor.typeText(action.answer)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.executeNextAction(actions: actions, index: index + 1, elements: elements, onDone: onDone)
                        }
                    }
                }
            }

        case "check", "radio", "uncheck":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                ClickExecutor.click(at: el.center)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.executeNextAction(actions: actions, index: index + 1, elements: elements, onDone: onDone)
                }
            }

        case "select":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                ClickExecutor.click(at: el.center)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    ClickExecutor.typeText(action.answer)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        ClickExecutor.pressKey("Enter")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.executeNextAction(actions: actions, index: index + 1, elements: elements, onDone: onDone)
                        }
                    }
                }
            }

        default:
            executeNextAction(actions: actions, index: index + 1, elements: elements, onDone: onDone)
        }
    }

    // MARK: - Agent Loop (Navigation Mode)

    private func agentLoop() {
        guard !isCancelled, isRunning else { return }

        iteration += 1

        if iteration > maxIterations {
            finish("Stopped — max steps")
            return
        }

        if consecutiveErrors >= 3 {
            statusBar.setError()
            finish("Stopped — repeated errors")
            return
        }

        print("[Agent] Thinking... (\(iteration))")
        statusBar.update("Thinking... (\(iteration))")
        statusBar.setActive()

        // Ensure target app is frontmost before scanning
        ensureFocus()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, !self.isCancelled, self.isRunning else { return }

            guard let targetApp = self.targetApp,
                  let scan = self.visionClickController.scanScreen(targetApp: targetApp),
                  let base64 = self.visionClickController.imageToBase64JPEG(scan.image) else {
                self.finish("Screen capture failed")
                return
            }

            // Frame diff detection (Step 1)
            if let prev = self.previousScreenshot {
                self.lastFrameDiff = VisionClickController.frameSimilarity(prev, scan.image)
                print("[Agent] Frame diff: \(String(format: "%.1f%%", (1.0 - self.lastFrameDiff) * 100)) changed")
            }
            self.previousScreenshot = scan.image

            // Advance plan step if screen changed significantly
            if self.lastFrameDiff < 0.90 && self.iteration > 1 && !self.plan.isEmpty {
                self.currentPlanStep = min(self.currentPlanStep + 1, self.plan.count - 1)
                self.actionsOnCurrentStep = 0
            }

            // If stuck on a plan step too long, abandon plan
            if self.actionsOnCurrentStep >= 4 && !self.plan.isEmpty {
                print("[Agent] Stuck on plan step \(self.currentPlanStep + 1), abandoning plan")
                self.plan = []
            }

            let elementList = self.visionClickController.buildElementList(elements: scan.elements)
            self.think(base64: base64, elementList: elementList, elements: scan.elements)
        }
    }

    // MARK: - Think (model chosen dynamically)

    private func think(base64: String, elementList: String, elements: [VisionClickController.ScreenElement]) {
        guard !isCancelled, isRunning else { return }

        var historyStr = ""
        for (i, entry) in actionHistory.enumerated() {
            historyStr += "  \(i + 1). \(entry)\n"
        }

        let stepsLeft = maxIterations - iteration
        let answersContext = solvedAnswers.isEmpty ? "" : "\nSOLVED ANSWERS (use these when typing):\n\(solvedAnswers)\n"
        let skillContext = currentSkill.isEmpty ? "" : "\n\(currentSkill)\n"
        let planStr = planContext()

        // Frame diff warning (Step 1)
        let frameDiffWarning: String
        if lastFrameDiff > 0.95 && iteration > 1 {
            frameDiffWarning = "\nWARNING: Screen appears UNCHANGED after your last action. Your click/type likely had no effect. Try a DIFFERENT element or strategy.\n"
        } else {
            frameDiffWarning = ""
        }

        // Retry budget hint (Step 4)
        let retryHint: String
        if sameTargetClicks >= 3 {
            retryHint = "\nWARNING: You have clicked the same element \(sameTargetClicks) times with no effect. Try a completely different approach or say DONE.\n"
        } else {
            retryHint = ""
        }

        // Bounds block feedback — tell LLM why its click was rejected
        let boundsHint: String
        if !lastBoundsBlockReason.isEmpty {
            boundsHint = "\nLAST CLICK REJECTED: \(lastBoundsBlockReason)\n"
        } else {
            boundsHint = ""
        }

        let prompt = """
        You are an AI agent controlling a macOS computer. You see the screen and decide ONE next action.

        GOAL: \(goal)
        \(skillContext)\(planStr)
        \(historyStr.isEmpty ? "" : "ACTIONS COMPLETED (\(actionHistory.count) so far, \(stepsLeft) steps remaining):\n\(historyStr)\n")\(answersContext)\(frameDiffWarning)\(retryHint)\(boundsHint)CURRENT SCREEN ELEMENTS:
        \(elementList)

        ACTIONS (respond with ONE JSON object):
        {"action":"CLICK","element":5,"reasoning":"..."}  — Single-click element by number
        {"action":"DOUBLE_CLICK","element":5,"reasoning":"..."}  — Double-click element (to open files, select words, play songs in lists)
        {"action":"TYPE","value":"text to type","reasoning":"..."}  — Type into focused field
        {"action":"TYPE_AND_SUBMIT","value":"search text","reasoning":"..."}  — Type text and press Enter (for search bars, URL fields)
        {"action":"KEY","value":"Enter","reasoning":"..."}  — Press Enter/Tab/Escape/Space/arrows ONLY
        {"action":"SCROLL","value":"down","reasoning":"..."}  — Scroll page up or down
        {"action":"WAIT","value":"2","reasoning":"..."}  — Wait seconds for loading
        {"action":"SOLVE","reasoning":"..."}  — Ask the smart AI to analyze and solve problems
        {"action":"DONE","reasoning":"..."}  — Goal achieved, STOP
        {"action":"STUCK","reasoning":"..."}  — Cannot proceed, STOP

        RULES:
        1. For CLICK, use element NUMBER from list. Prefer [app window] over [menu bar]/[dock].
        2. To type into a field: CLICK the input element first, NOT the label.
        3. Use TYPE_AND_SUBMIT when typing into a search bar or URL field — it types and presses Enter in one step.
        4. After typing (not TYPE_AND_SUBMIT), use KEY Tab or Enter to proceed.
        5. NO Cmd+shortcuts. Only Enter, Tab, Escape, Space, arrows.
        6. If you see empty answer boxes and don't know what to type, use SOLVE.
        7. If you already have SOLVED ANSWERS above, use those values — don't SOLVE again.
        8. Say DONE when goal is achieved. Verify by looking at the screenshot.
        9. \(stepsLeft) steps left. Be efficient.
        10. SUCCESS: If media is playing (pause button visible, progress bar advancing), say DONE. If a page loaded, search results appeared, or an app opened — the step worked.
        11. NO LOOPS: If the screen is unchanged after your action, do NOT repeat it. Try something different.
        12. Elements marked ⚠️ have low OCR confidence — prefer other elements if available.

        Respond with a single JSON object. No markdown. No explanation.
        """

        let model = chooseModel(elements: elements)

        callClaude(base64Image: base64, prompt: prompt, model: model) { [weak self] response in
            guard let self = self, !self.isCancelled, self.isRunning else { return }

            print("[Agent] Raw response (\(model == self.sonnetModel ? "Sonnet" : "Haiku")): \(response.prefix(200))")

            guard let json = self.extractJSON(from: response),
                  let action = json["action"] as? String else {
                // JSON parse retry (Step 2) — retry once with same screenshot
                print("[Agent] Parse failed, retrying same screenshot...")
                let retryPrompt = prompt + "\n\nYour previous response was not valid JSON. Respond with ONLY a single valid JSON object."
                self.callClaude(base64Image: base64, prompt: retryPrompt, model: model) { [weak self] retryResponse in
                    guard let self = self, !self.isCancelled, self.isRunning else { return }
                    guard let json = self.extractJSON(from: retryResponse),
                          let action = json["action"] as? String else {
                        print("[Agent] Parse retry also failed")
                        self.consecutiveErrors += 1
                        self.actionHistory.append("(parse error)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.agentLoop() }
                        return
                    }
                    self.consecutiveErrors = 0
                    self.actionsOnCurrentStep += 1
                    self.act(action: action, json: json, elements: elements)
                }
                return
            }

            self.consecutiveErrors = 0
            self.actionsOnCurrentStep += 1
            let reasoning = json["reasoning"] as? String ?? ""
            print("[Agent] Action: \(action) — \(reasoning)")

            self.act(action: action, json: json, elements: elements)
        }
    }

    // MARK: - Model Routing (Step 12)

    private func chooseModel(elements: [VisionClickController.ScreenElement]) -> String {
        // After TYPE, next step is usually Enter/Tab — Haiku is fine
        if let last = actionHistory.last, last.hasPrefix("TYPE") { return haikuModel }

        // Following solved answers — Haiku can handle
        if !solvedAnswers.isEmpty { return haikuModel }

        // Screen unchanged (stuck) — upgrade to Sonnet for smarter reasoning
        if lastFrameDiff > 0.95 && iteration > 2 { return sonnetModel }

        // Complex UI with many elements — Sonnet handles better
        if elements.count > 60 { return sonnetModel }

        // Simple UI — Haiku is faster and cheaper
        if elements.count < 20 { return haikuModel }

        // Default
        return haikuModel
    }

    // MARK: - Solve (navigation mode)

    private func solve(base64: String, elementList: String) {
        print("[Agent] Solving... (Sonnet)")
        statusBar.update("Solving...")
        actionHistory.append("SOLVE — analyzing page")

        let prompt = """
        You are looking at a homework/quiz page. There are empty answer fields that need to be filled in.

        Read the full question visible on screen. Understand the problem completely before solving.

        DETECTED ELEMENTS:
        \(elementList)

        For each empty answer field, determine what answer it expects based on:
        - The label immediately to its left (e.g., "R =", "I =", "f(x) =")
        - The question text above it (shown as "above:" context)
        - The instructions (e.g., "Enter your answer using interval notation")

        Solve the problem. Return FILL lines:
        FILL:element_number=answer

        RULES:
        - Use element NUMBER from brackets [N].
        - Only fill empty answer boxes — skip buttons, labels, filled boxes.
        - Be precise with formatting (interval notation, exact answers).
        - Nothing else — just FILL lines.
        """

        callClaude(base64Image: base64, prompt: prompt, model: sonnetModel) { [weak self] response in
            guard let self = self, !self.isCancelled, self.isRunning else { return }

            let fills = response.components(separatedBy: "\n")
                .filter { $0.uppercased().hasPrefix("FILL:") }
                .map { line -> String in
                    let content = String(line.dropFirst(5))
                    let parts = content.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        return "→ CLICK element [\(parts[0].trimmingCharacters(in: .whitespaces))], then TYPE: \(parts[1].trimmingCharacters(in: .whitespaces))"
                    }
                    return line
                }

            if fills.isEmpty {
                self.solvedAnswers = "No empty boxes found to fill."
                self.actionHistory.append("SOLVE — no answers needed")
            } else {
                self.solvedAnswers = "INSTRUCTIONS (do these in order):\n" + fills.joined(separator: "\n")
                self.actionHistory.append("SOLVE — found \(fills.count) answers to fill")
            }

            print("[Agent] Solved \(fills.count) answers")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.agentLoop() }
        }
    }

    // MARK: - Focus Guard System

    /// Get the full window frame (including title bar + toolbar) of the target app.
    /// Uses CGWindowList which returns the complete window bounds, not just content area.
    private func getTargetAppBounds() -> CGRect? {
        guard let targetApp = targetApp else { return nil }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        // Find windows belonging to target app, layer 0 = normal windows
        let appWindows = windowList.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == targetApp.processIdentifier &&
            ($0[kCGWindowLayer as String] as? Int) == 0 &&
            ($0[kCGWindowAlpha as String] as? Double ?? 0) > 0
        }

        // Pick the largest window (main window)
        var bestFrame: CGRect?
        var bestArea: CGFloat = 0

        for window in appWindows {
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"] else { continue }

            let area = w * h
            if area > bestArea {
                bestArea = area
                bestFrame = CGRect(x: x, y: y, width: w, height: h)
            }
        }

        return bestFrame
    }

    /// Check if a point is inside the target app's windows OR dock/menu bar.
    private func isPointInTargetApp(_ point: CGPoint) -> Bool {
        if let bounds = getTargetAppBounds(), bounds.contains(point) {
            return true
        }
        // Allow dock and menu bar clicks (needed for opening apps)
        let screenH = NSScreen.main?.frame.height ?? 900
        if point.y < 30 || point.y > screenH - 70 { return true }
        return false
    }

    /// Layer 1: Ensure target app is frontmost before acting. Returns true if focused.
    @discardableResult
    private func ensureFocus() -> Bool {
        guard let targetApp = targetApp else { return false }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == targetApp.processIdentifier {
            return true
        }

        // Wrong app is frontmost — refocus
        print("[Focus] Wrong app frontmost (\(frontmost?.localizedName ?? "?")), refocusing \(targetApp.localizedName ?? "?")")
        targetApp.activate(options: [.activateIgnoringOtherApps])
        usleep(300_000) // 300ms for activation
        return true
    }

    /// Layer 2: Check focus after an action. Returns true if focus is still correct.
    /// If lost, recovers focus and signals that a fresh scan is needed.
    private func validateFocusAfterAction() -> Bool {
        guard let targetApp = targetApp else { return false }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == targetApp.processIdentifier {
            return true
        }

        // Focus was lost — recover
        print("[Focus] Focus LOST after action (now: \(frontmost?.localizedName ?? "?")). Recovering...")
        targetApp.activate(options: [.activateIgnoringOtherApps])
        usleep(500_000) // 500ms for recovery
        actionHistory.append("FOCUS RECOVERED — app lost focus, refocused")
        return false
    }

    /// Detect if a click is an intentional app switch (DockItem, menu bar, or dock area).
    private func isAppSwitchClick(label: String, point: CGPoint) -> Bool {
        let screenH = NSScreen.main?.frame.height ?? 900
        if label.contains("DockItem") { return true }
        if point.y > screenH - 70 { return true }
        if point.y < 30 { return true }
        return false
    }

    /// Detect if a click targets system-managed UI (menus, menu items) that float
    /// outside the app window frame. These are always safe to click.
    private func isSystemUIClick(label: String) -> Bool {
        let systemPatterns = ["MenuItem", "MenuBarItem", "MenuButton", "Menu]"]
        return systemPatterns.contains(where: { label.contains($0) })
    }

    /// Full safe action execution with the 6-step focus guard:
    /// 1. Bounds check → 2. Focus check → 3. Execute → 4. Post-focus check → 5. Frame diff → 6. Continue
    private func safeClick(at point: CGPoint, label: String, isDoubleClick: Bool = false, completion: @escaping () -> Void) {
        let intentionalSwitch = isAppSwitchClick(label: label, point: point)
        let systemUI = isSystemUIClick(label: label)
        let skipBoundsCheck = intentionalSwitch || systemUI

        // Step 1: Bounds check (skip for app switches, menu items, and system UI)
        if !skipBoundsCheck && !isPointInTargetApp(point) {
            outsideAppClickCount += 1

            let boundsDesc: String
            if let bounds = getTargetAppBounds() {
                boundsDesc = "Valid window area: (\(Int(bounds.minX)),\(Int(bounds.minY))) to (\(Int(bounds.maxX)),\(Int(bounds.maxY))). Your click at (\(Int(point.x)),\(Int(point.y))) is outside. Choose an element within the window bounds."
            } else {
                boundsDesc = "Click at (\(Int(point.x)),\(Int(point.y))) is outside the app window. Choose a different element."
            }

            print("[Focus] CLICK blocked — \(boundsDesc)")
            actionHistory.append("CLICK REJECTED: \(label) — outside bounds")
            lastBoundsBlockReason = boundsDesc

            if outsideAppClickCount >= 3 {
                statusBar.setPaused()
                finish("Paused — clicking outside app", delay: 2.0)
                return
            }

            consecutiveErrors += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { completion() }
            return
        }
        outsideAppClickCount = 0
        lastBoundsBlockReason = ""

        // Step 2: Pre-click focus check (skip for dock clicks — we're switching apps on purpose)
        if !intentionalSwitch {
            ensureFocus()
        }

        // Step 3: Execute click
        if isDoubleClick {
            ClickExecutor.doubleClick(at: point)
        } else {
            ClickExecutor.click(at: point)
        }
        let clickType = isDoubleClick ? "DOUBLE_CLICK" : "CLICK"
        print("[Agent] \(clickType): \(label.prefix(30)) at (\(Int(point.x)),\(Int(point.y)))")
        actionHistory.append("\(clickType) \(label)")

        // Step 4: Post-click focus validation
        let delay: TimeInterval = intentionalSwitch ? 0.8 : 0.3  // longer delay for app switches
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isCancelled, self.isRunning else { return }

            if intentionalSwitch {
                // Intentional app switch — adopt the new frontmost app as target
                if let newFront = NSWorkspace.shared.frontmostApplication,
                   newFront.processIdentifier != self.targetApp?.processIdentifier {
                    print("[Focus] App switched to \(newFront.localizedName ?? "?") (intentional)")
                    self.targetApp = newFront
                    self.actionHistory.append("TARGET APP → \(newFront.localizedName ?? "?")")
                }
            } else {
                let focusOK = self.validateFocusAfterAction()
                if !focusOK {
                    print("[Focus] Focus recovered after click. Will take fresh screenshot.")
                }
            }

            // Step 5 & 6 happen in agentLoop (frame diff + next reasoning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion()
            }
        }
    }

    /// Safe wrapper for type/key/scroll actions — ensures focus before and after.
    private func safeAction(label: String, action: @escaping () -> Void, completion: @escaping () -> Void) {
        ensureFocus()
        action()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, !self.isCancelled, self.isRunning else { return }

            let focusOK = self.validateFocusAfterAction()
            if !focusOK {
                print("[Focus] Focus recovered after \(label)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                completion()
            }
        }
    }

    // MARK: - Act

    private func act(action: String, json: [String: Any], elements: [VisionClickController.ScreenElement]) {
        guard !isCancelled, isRunning else { return }

        // Reset consecutive wait counter for non-WAIT actions
        if action.uppercased() != "WAIT" {
            consecutiveWaits = 0
        }

        switch action.uppercased() {

        case "CLICK":
            let idx: Int
            if let n = json["element"] as? Int { idx = n - 1 }
            else if let s = json["element"] as? String, let n = Int(s) { idx = n - 1 }
            else {
                actionHistory.append("CLICK failed — no element number")
                consecutiveErrors += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.agentLoop() }
                return
            }

            guard idx >= 0, idx < elements.count else {
                actionHistory.append("CLICK failed — element \(idx+1) out of range")
                consecutiveErrors += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.agentLoop() }
                return
            }

            let el = elements[idx]

            // Destructive action check (Step 10)
            let labelLower = el.label.lowercased()
            if dangerousPatterns.contains(where: { labelLower.contains($0) }) {
                print("[Agent] Dangerous action detected: \(el.label)")
                statusBar.setPaused()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let alert = NSAlert()
                    alert.messageText = "Confirm Action"
                    alert.informativeText = "The agent wants to click: \"\(el.label)\"\n\nAllow this action?"
                    alert.addButton(withTitle: "Allow")
                    alert.addButton(withTitle: "Block")
                    alert.alertStyle = .warning

                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        self.statusBar.setActive()
                        self.executeClick(el: el)
                    } else {
                        self.statusBar.setActive()
                        self.actionHistory.append("CLICK blocked by user: \(el.label)")
                        self.ensureFocus()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.agentLoop() }
                    }
                }
                return
            }

            // Retry budget tracking (Step 4)
            if let lastCenter = lastClickCenter,
               abs(el.center.x - lastCenter.x) < 30 && abs(el.center.y - lastCenter.y) < 30 {
                sameTargetClicks += 1

                if sameTargetClicks >= 2 && lastFrameDiff > 0.95 {
                    print("[Agent] Stuck — forcing scroll instead of repeated click")
                    actionHistory.append("FORCED SCROLL — stuck on same element")
                    sameTargetClicks = 0
                    lastClickCenter = nil
                    safeAction(label: "SCROLL") {
                        ClickExecutor.scroll(direction: "down")
                    } completion: { [weak self] in
                        self?.agentLoop()
                    }
                    return
                }
            } else {
                sameTargetClicks = 1
            }
            lastClickCenter = el.center

            executeClick(el: el)

        case "DOUBLE_CLICK":
            let dblIdx: Int
            if let n = json["element"] as? Int { dblIdx = n - 1 }
            else if let s = json["element"] as? String, let n = Int(s) { dblIdx = n - 1 }
            else {
                actionHistory.append("DOUBLE_CLICK failed — no element number")
                consecutiveErrors += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.agentLoop() }
                return
            }

            guard dblIdx >= 0, dblIdx < elements.count else {
                actionHistory.append("DOUBLE_CLICK failed — element \(dblIdx+1) out of range")
                consecutiveErrors += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.agentLoop() }
                return
            }

            let dblEl = elements[dblIdx]

            DispatchQueue.main.async { [weak self] in
                self?.safeClick(at: dblEl.center, label: dblEl.label, isDoubleClick: true) {
                    self?.agentLoop()
                }
            }

        case "TYPE":
            let value = jsonString(json, "value") ?? ""
            guard !value.isEmpty else {
                actionHistory.append("TYPE — empty value")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.agentLoop() }
                return
            }
            print("[Agent] Type: \(value.prefix(25))")
            actionHistory.append("TYPE \"\(value)\"")

            safeAction(label: "TYPE") {
                ClickExecutor.typeText(value)
            } completion: { [weak self] in
                self?.agentLoop()
            }

        case "TYPE_AND_SUBMIT":
            let value = jsonString(json, "value") ?? ""
            guard !value.isEmpty else {
                actionHistory.append("TYPE_AND_SUBMIT — empty value")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.agentLoop() }
                return
            }
            print("[Agent] Type+Submit: \(value.prefix(25))")
            actionHistory.append("TYPE_AND_SUBMIT \"\(value)\"")

            safeAction(label: "TYPE_AND_SUBMIT") {
                ClickExecutor.typeText(value)
                usleep(200_000)
                ClickExecutor.pressKey("Enter")
            } completion: { [weak self] in
                // Longer delay after submit for page to respond
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self?.agentLoop()
                }
            }

        case "KEY":
            let value = jsonString(json, "value") ?? "Enter"
            print("[Agent] Key: \(value)")
            actionHistory.append("KEY \(value)")

            safeAction(label: "KEY \(value)") {
                ClickExecutor.pressKey(value)
            } completion: { [weak self] in
                self?.agentLoop()
            }

        case "SCROLL":
            let direction = jsonString(json, "value") ?? "down"
            print("[Agent] Scroll \(direction)")
            actionHistory.append("SCROLL \(direction)")

            safeAction(label: "SCROLL") {
                ClickExecutor.scroll(direction: direction)
            } completion: { [weak self] in
                self?.agentLoop()
            }

        case "SOLVE":
            ensureFocus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self,
                      let targetApp = self.targetApp,
                      let scan = self.visionClickController.scanScreen(targetApp: targetApp),
                      let base64 = self.visionClickController.imageToBase64JPEG(scan.image) else {
                    self?.actionHistory.append("SOLVE failed — no screenshot")
                    self?.agentLoop()
                    return
                }
                let elementList = self.visionClickController.buildElementList(elements: scan.elements)
                self.solve(base64: base64, elementList: elementList)
            }

        case "WAIT":
            consecutiveWaits += 1
            if consecutiveWaits >= 3 {
                print("[Agent] Too many consecutive WAITs, moving on")
                actionHistory.append("WAIT — skipped (3 consecutive)")
                consecutiveWaits = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.agentLoop() }
                return
            }

            let seconds: Double
            if let n = json["value"] as? Double { seconds = n }
            else if let n = json["value"] as? Int { seconds = Double(n) }
            else if let s = json["value"] as? String, let n = Double(s) { seconds = n }
            else { seconds = 2.0 }

            print("[Agent] Waiting \(Int(seconds))s...")
            actionHistory.append("WAIT \(Int(seconds))s")

            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.agentLoop()
            }

        case "DONE":
            actionHistory.append("DONE")
            finish("Done!")

        case "STUCK":
            let reasoning = json["reasoning"] as? String ?? "unknown"
            actionHistory.append("STUCK")
            statusBar.setError()
            finish("Stuck: \(String(reasoning.prefix(30)))", delay: 3.0)

        default:
            actionHistory.append("UNKNOWN:\(action)")
            consecutiveErrors += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.agentLoop() }
        }
    }

    // MARK: - Click Helper (with full focus guard)

    private func executeClick(el: VisionClickController.ScreenElement) {
        DispatchQueue.main.async { [weak self] in
            self?.safeClick(at: el.center, label: el.label) {
                self?.agentLoop()
            }
        }
    }

    // MARK: - Claude API

    private func callClaude(base64Image: String, prompt: String, model: String, completion: @escaping (String) -> Void) {
        var fullResponse = ""

        APIService.shared.sendScreenshot(
            base64Image,
            prompt: prompt,
            model: model,
            onChunk: { chunk in fullResponse += chunk },
            onComplete: { _, _ in
                completion(fullResponse.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            onError: { error in
                print("[Agent] API error: \(error.localizedDescription)")
                completion("{}")
            }
        )
    }

    // MARK: - JSON Parsing

    private func extractJSON(from text: String) -> [String: Any]? {
        let cleaned = stripMarkdownFences(text)

        // Try parsing the whole string first
        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        // Find the first complete JSON object using bracket matching.
        // Handles trailing text like: {"action":"CLICK"} Here's why I chose...
        guard let openIdx = cleaned.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var endIdx: String.Index?

        for i in cleaned.indices[openIdx...] {
            let ch = cleaned[i]

            if escaped {
                escaped = false
                continue
            }

            if ch == "\\" && inString {
                escaped = true
                continue
            }

            if ch == "\"" {
                inString = !inString
                continue
            }

            if inString { continue }

            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    endIdx = i
                    break
                }
            }
        }

        guard let end = endIdx else { return nil }

        let jsonStr = String(cleaned[openIdx...end])
        if let data = jsonStr.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        return nil
    }

    private func jsonString(_ json: [String: Any], _ key: String) -> String? {
        if let s = json[key] as? String { return s }
        if let n = json[key] as? Int { return String(n) }
        if let n = json[key] as? Double { return String(n) }
        return nil
    }

    private func stripMarkdownFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            if let nl = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: nl)...])
            }
        }
        if result.hasSuffix("```") { result = String(result.dropLast(3)) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Image

    private func imageToBase64JPEG(_ image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return jpeg.base64EncodedString()
    }
}
