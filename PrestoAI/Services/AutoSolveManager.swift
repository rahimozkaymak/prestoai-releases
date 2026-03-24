import AppKit

class AutoSolveManager {

    static let shared = AutoSolveManager()

    private(set) var isActive = false
    private var bubbles: [Int: AnswerBubbleWindow] = [:]
    private var scanTimer: Timer?
    private var previousScreenshot: CGImage?
    private var solverTasks: [Task<Void, Never>] = []
    private var sessionId: String?
    private var isIdentifyInFlight = false
    private var isFirstCapture = true

    // Compressed image width (pixels) actually sent to the coordinator — used for bbox → screen coord conversion
    private var compressedImageWidth: Int = 1024

    private init() {}

    // MARK: - Lifecycle

    func activate(sessionId: String) {
        guard !isActive else { return }
        isActive = true
        self.sessionId = sessionId
        isFirstCapture = true
        previousScreenshot = nil
        print("[AutoSolve] Activated, session: \(sessionId)")
        captureAndIdentify()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.captureAndIdentify()
        }
    }

    func deactivate() {
        isActive = false
        for task in solverTasks { task.cancel() }
        solverTasks.removeAll()
        scanTimer?.invalidate()
        scanTimer = nil
        isIdentifyInFlight = false
        DispatchQueue.main.async { [weak self] in
            self?.clearBubbles()
        }
        previousScreenshot = nil
        sessionId = nil
        print("[AutoSolve] Deactivated — all tasks cancelled, bubbles cleared")
    }

    // MARK: - Capture + Identify

    private func captureAndIdentify() {
        guard isActive, !isIdentifyInFlight else { return }
        isIdentifyInFlight = true

        Task { [weak self] in
            guard let self = self else { return }
            defer { self.isIdentifyInFlight = false }
            await self.performCaptureAndIdentify()
        }
    }

    private func performCaptureAndIdentify() async {
        guard isActive else { return }

        guard let (cgImage, base64) = await captureScreen() else { return }
        guard isActive else { return }

        // Similarity check — skip if screen hasn't changed (bypass on first capture)
        if !isFirstCapture, let prev = previousScreenshot {
            if frameSimilarity(prev, cgImage) >= 0.85 {
                return
            }
        }
        isFirstCapture = false
        previousScreenshot = cgImage

        // Compress: 1024px max, JPEG 60%
        let (compressed, _, compressedWidth) = ImageCompressor.compressForStudy(base64)
        compressedImageWidth = compressedWidth

        let sid = sessionId ?? ""
        let deviceId = AppStateManager.shared.deviceID

        do {
            let result = try await APIService.shared.identifyQuestions(
                image: compressed,
                sessionId: sid,
                deviceId: deviceId
            )

            guard isActive else { return }
            print("[AutoSolve] Questions found: \(result.questions.count)")
            for q in result.questions {
                print("[AutoSolve] Q\(q.id): \(q.questionText.prefix(80))... bbox=\(q.bbox)")
            }

            if result.questions.isEmpty { return }

            // Cancel in-flight solvers, clear existing bubbles
            for task in solverTasks { task.cancel() }
            solverTasks.removeAll()
            await MainActor.run { clearBubbles() }

            let globalContext = result.globalContext
            for q in result.questions {
                print("[AutoSolve] Launching solver for Q\(q.id)")
                let task = Task { [weak self] in
                    guard let self = self else { return }
                    await self.solveQuestion(
                        id: q.id,
                        questionText: q.questionText,
                        globalContext: globalContext,
                        hint: q.answerBoxHint,
                        bbox: q.bbox
                    )
                }
                solverTasks.append(task)
            }
        } catch {
            print("[AutoSolve] Identify error: \(error.localizedDescription)")
        }
    }

    // MARK: - Solve (per question)

    private func solveQuestion(id: Int, questionText: String, globalContext: String,
                               hint: String, bbox: CGRect) async {
        guard isActive else { return }

        do {
            let result = try await APIService.shared.solveQuestion(
                questionText: questionText,
                globalContext: globalContext,
                answerBoxHint: hint,
                sessionId: sessionId ?? "",
                deviceId: AppStateManager.shared.deviceID
            )

            guard isActive else { return }
            print("[AutoSolve] Solver Q\(id) completed: latex=\(result.answerLatex.prefix(50))")

            await MainActor.run { [weak self] in
                guard let self = self, self.isActive else { return }
                self.showBubble(id: id, answerLatex: result.answerLatex,
                                answerCopyable: result.answerCopyable, bbox: bbox)
            }
        } catch {
            print("[AutoSolve] Solver Q\(id) FAILED: \(error)")
        }
    }

    // MARK: - Bubble Management

    @MainActor
    private func showBubble(id: Int, answerLatex: String, answerCopyable: String, bbox: CGRect) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Scale from compressed image space → screen points
        // compressedImageWidth is the actual pixel width of the JPEG sent to the coordinator
        let imageScale = screenFrame.width / CGFloat(compressedImageWidth)

        // Convert bbox (top-down image coords) to screen points (top-down)
        let questionX = bbox.origin.x * imageScale
        let questionY = bbox.origin.y * imageScale
        let questionW = bbox.size.width * imageScale
        let questionH = bbox.size.height * imageScale

        // Flip Y: AppKit origin is bottom-left; bbox Y is top-down
        let flippedY = screenFrame.height - (questionY + questionH)

        print("[AutoSolve] Screen: \(screenFrame), imageScale: \(imageScale)")
        print("[AutoSolve] Q\(id) bbox: \(bbox) → screen position: (\(questionX + questionW + 12), \(flippedY + questionH / 2))")

        let bubbleWidth: CGFloat = 280
        let bubbleHeight: CGFloat = 60  // initial; auto-resizes after MathJax renders

        // Position to the right of bbox, vertically centered on question
        var bubbleX = questionX + questionW + 12
        var bubbleY = flippedY + (questionH / 2) - (bubbleHeight / 2)

        // If bubble would clip off the right edge, put it to the left instead
        if bubbleX + bubbleWidth > screenFrame.width - 20 {
            bubbleX = questionX - bubbleWidth - 12
        }

        // Overlap prevention: push new bubble below any existing overlap
        var proposed = CGRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
        for (_, existing) in bubbles {
            if proposed.intersects(existing.frame) {
                bubbleY = existing.frame.minY - bubbleHeight - 10
                proposed = CGRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
            }
        }

        let bubbleFrame = NSRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
        print("[AutoSolve] Bubble Q\(id) created at frame=\(bubbleFrame)")
        let bubble = AnswerBubbleWindow(
            answerLatex: answerLatex,
            answerCopyable: answerCopyable,
            initialFrame: bubbleFrame
        )
        bubble.show()
        bubbles[id] = bubble
    }

    @MainActor
    private func clearBubbles() {
        for (_, bubble) in bubbles {
            bubble.fadeOut()
        }
        bubbles.removeAll()
    }

    // MARK: - Screen Capture

    private func captureScreen() async -> (CGImage, String)? {
        guard CGPreflightScreenCaptureAccess() else {
            print("[AutoSolve] No screen recording permission")
            return nil
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
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

                continuation.resume(returning: (cgImage, pngData.base64EncodedString()))
            }
        }
    }

    // MARK: - Frame Similarity (pixel-sampled, ~196 points)

    private func frameSimilarity(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return 0.0 }
        guard let dataA = a.dataProvider?.data as Data?,
              let dataB = b.dataProvider?.data as Data? else { return 0.0 }

        let bprA = a.bytesPerRow, bppA = a.bitsPerPixel / 8
        let bprB = b.bytesPerRow, bppB = b.bitsPerPixel / 8
        let grid = 14, tolerance = 10
        var matches = 0

        for row in 0..<grid {
            let y = row * a.height / grid
            for col in 0..<grid {
                let x = col * a.width / grid
                let oA = y * bprA + x * bppA
                let oB = y * bprB + x * bppB
                guard oA + 2 < dataA.count, oB + 2 < dataB.count else { continue }
                let rD = abs(Int(dataA[oA]) - Int(dataB[oB]))
                let gD = abs(Int(dataA[oA + 1]) - Int(dataB[oB + 1]))
                let bD = abs(Int(dataA[oA + 2]) - Int(dataB[oB + 2]))
                if rD <= tolerance && gD <= tolerance && bD <= tolerance { matches += 1 }
            }
        }

        return Double(matches) / Double(grid * grid)
    }
}
