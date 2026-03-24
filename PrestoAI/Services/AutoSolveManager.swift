import AppKit
import Vision

// MARK: - QuestionRegion

/// Represents a detected question on screen with Vision-derived positioning data.
struct QuestionRegion {
    let id: Int
    let questionBounds: CGRect   // VN normalized coords (bottom-left origin, 0–1)
    let answerPlacement: CGPoint // VN normalized coords (bottom-left origin, 0–1) — bubble center
    let imageSize: CGSize        // pixel dimensions of the analyzed CGImage
}

// MARK: - AutoSolveManager

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
    private var solversInFlight = 0

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
        solversInFlight = 0
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
        guard solversInFlight == 0 else {
            print("[AutoSolve] Skipping re-scan — \(solversInFlight) solver(s) still in flight")
            return
        }
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
            if frameSimilarity(prev, cgImage) >= 0.85 { return }
        }
        isFirstCapture = false
        previousScreenshot = cgImage

        // Stage 0: local Vision layout analysis — no network, runs in milliseconds
        let regions = analyzeScreenLayout(screenshot: cgImage)
        print("[AutoSolve] Vision regions: \(regions.count)")

        // Compress image for coordinator
        let (compressed, _, _) = ImageCompressor.compressForStudy(base64)

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
                print("[AutoSolve] Q\(q.id): \(q.questionText.prefix(80))...")
            }

            if result.questions.isEmpty { return }

            // Cancel in-flight solvers, clear existing bubbles
            for task in solverTasks { task.cancel() }
            solverTasks.removeAll()
            await MainActor.run { clearBubbles() }

            let globalContext = result.globalContext
            solversInFlight = result.questions.count

            for q in result.questions {
                // Match coordinator question to Vision region by sequential order (Q1→regions[0])
                let region: QuestionRegion? = q.id <= regions.count ? regions[q.id - 1] : nil
                print("[AutoSolve] Launching solver Q\(q.id), hasRegion=\(region != nil)")
                let task = Task { [weak self] in
                    guard let self = self else { return }
                    await self.solveQuestion(
                        id: q.id,
                        questionText: q.questionText,
                        globalContext: globalContext,
                        hint: q.answerBoxHint,
                        region: region
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
                               hint: String, region: QuestionRegion?) async {
        defer {
            solversInFlight = max(0, solversInFlight - 1)
            if solversInFlight == 0 { solverTasks.removeAll() }
        }
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
                                answerCopyable: result.answerCopyable, region: region)
            }
        } catch {
            print("[AutoSolve] Solver Q\(id) FAILED: \(error)")
        }
    }

    // MARK: - Bubble Management

    @MainActor
    private func showBubble(id: Int, answerLatex: String, answerCopyable: String, region: QuestionRegion?) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let bubbleWidth: CGFloat = 280
        let bubbleHeight: CGFloat = 60  // initial; auto-resizes after MathJax renders

        var bubbleX: CGFloat
        var bubbleY: CGFloat

        if let region = region {
            let pos = imageToScreen(normalizedPoint: region.answerPlacement, imageSize: region.imageSize)
            // Center the bubble on the computed placement point
            bubbleX = pos.x - bubbleWidth / 2
            bubbleY = pos.y - bubbleHeight / 2
            print("[AutoSolve] Q\(id) VN placement=\(region.answerPlacement) → screen=(\(Int(pos.x)), \(Int(pos.y)))")
        } else {
            bubbleX = (screenFrame.width - bubbleWidth) / 2
            bubbleY = (screenFrame.height - bubbleHeight) / 2
            print("[AutoSolve] Q\(id) no region — fallback center")
        }

        // Clamp to screen bounds
        bubbleX = min(max(20, bubbleX), screenFrame.width - bubbleWidth - 20)
        bubbleY = min(max(20, bubbleY), screenFrame.height - bubbleHeight - 20)

        // Overlap prevention: push new bubble below any existing one
        var proposed = CGRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
        for (_, existing) in bubbles {
            if proposed.intersects(existing.frame) {
                bubbleY = existing.frame.minY - bubbleHeight - 10
                proposed = CGRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
            }
        }

        let bubbleFrame = NSRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
        print("[AutoSolve] Bubble Q\(id) created at \(bubbleFrame)")
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
        for (_, bubble) in bubbles { bubble.fadeOut() }
        bubbles.removeAll()
    }

    // MARK: - Vision Layout Analysis

    private struct TextBlock {
        let text: String
        let pixelBounds: CGRect  // top-left origin, pixel coordinates
        let vnBounds: CGRect     // VN normalized (bottom-left origin, 0–1)
    }

    private func analyzeScreenLayout(screenshot: CGImage) -> [QuestionRegion] {
        let imgW = CGFloat(screenshot.width)
        let imgH = CGFloat(screenshot.height)
        let imageSize = CGSize(width: imgW, height: imgH)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // faster; positions matter more than corrections

        let handler = VNImageRequestHandler(cgImage: screenshot, options: [:])
        try? handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            print("[AutoSolve] Vision: no text found on screen")
            return []
        }

        // Convert observations to TextBlocks sorted top-to-bottom (ascending pixel Y)
        let blocks: [TextBlock] = observations.compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            let vn = obs.boundingBox
            // VN → pixel (top-left origin): flip Y axis
            let px = CGRect(
                x: vn.origin.x * imgW,
                y: (1.0 - vn.origin.y - vn.size.height) * imgH,
                width: vn.size.width * imgW,
                height: vn.size.height * imgH
            )
            return TextBlock(text: top.string, pixelBounds: px, vnBounds: vn)
        }.sorted { $0.pixelBounds.origin.y < $1.pixelBounds.origin.y }

        // Patterns that identify the start of a question
        let questionPatterns: [String] = [
            #"^\[?\d+[A-Za-z]?\.?\]?\s*[\[\(]?\d*\s*points?\s*[\]\)]?"#,
            #"^Question\s+\d+"#,
            #"^Problem\s+\d+"#,
            #"^\d+\.\s"#,
            #"^\[\d+[A-Z]?\.\]"#,
            #"^Part\s+[a-z]"#
        ]

        func isQuestionStart(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespaces)
            return questionPatterns.contains { t.range(of: $0, options: .regularExpression) != nil }
        }

        let startIndices = blocks.indices.filter { isQuestionStart(blocks[$0].text) }
        guard !startIndices.isEmpty else {
            print("[AutoSolve] Vision: no question patterns found in \(blocks.count) text blocks")
            return []
        }
        print("[AutoSolve] Vision: \(startIndices.count) question(s) detected, \(blocks.count) total text blocks")

        var regions: [QuestionRegion] = []

        for (qi, startIdx) in startIndices.enumerated() {
            let endIdx = qi + 1 < startIndices.count ? startIndices[qi + 1] : blocks.count
            let qBlocks = Array(blocks[startIdx..<endIdx])

            // Pixel bounding rect covering all text in this question group
            let qBounds = qBlocks.reduce(CGRect.null) { $0.union($1.pixelBounds) }

            // Y coordinate of the next question's first line (or image bottom)
            let nextQY: CGFloat = qi + 1 < startIndices.count
                ? blocks[startIndices[qi + 1]].pixelBounds.origin.y
                : imgH

            // Determine answer placement in pixel space, then convert to VN normalized
            let placementPx = answerPlacementPixel(
                qBlocks: qBlocks, qBounds: qBounds,
                nextQuestionY: nextQY, centerX: qBounds.midX
            )
            let placementVN = CGPoint(
                x: placementPx.x / imgW,
                y: 1.0 - placementPx.y / imgH  // pixel top-left → VN bottom-left
            )

            // VN bounds of the question block
            let vnBounds = CGRect(
                x: qBounds.origin.x / imgW,
                y: 1.0 - (qBounds.origin.y + qBounds.height) / imgH,
                width: qBounds.width / imgW,
                height: qBounds.height / imgH
            )

            print("[AutoSolve] Vision Q\(qi + 1): px=\(qBounds.integral), placementPx=(\(Int(placementPx.x)), \(Int(placementPx.y)))")

            regions.append(QuestionRegion(
                id: qi + 1,
                questionBounds: vnBounds,
                answerPlacement: placementVN,
                imageSize: imageSize
            ))
        }

        return regions
    }

    /// Computes where to place the answer bubble in pixel coordinates (top-left origin).
    private func answerPlacementPixel(qBlocks: [TextBlock], qBounds: CGRect,
                                      nextQuestionY: CGFloat, centerX: CGFloat) -> CGPoint {
        // 1. "SHOW YOUR WORK:" → place bubble just above it
        if let showWork = qBlocks.first(where: { $0.text.uppercased().hasPrefix("SHOW YOUR WORK") }) {
            let lastAbove = qBlocks
                .filter { $0.pixelBounds.maxY <= showWork.pixelBounds.origin.y }
                .max(by: { $0.pixelBounds.maxY < $1.pixelBounds.maxY })
            let y = lastAbove.map { $0.pixelBounds.maxY + 8 } ?? (showWork.pixelBounds.origin.y - 8)
            return CGPoint(x: centerX, y: y)
        }

        // 2. Last multiple choice option [a]–[e] / (a)–(e) → place just below it
        let mcPattern = #"^[\[\(][a-eA-E][\]\)][.\s]"#
        let choices = qBlocks.filter { $0.text.range(of: mcPattern, options: .regularExpression) != nil }
        if let last = choices.max(by: { $0.pixelBounds.maxY < $1.pixelBounds.maxY }) {
            return CGPoint(x: centerX, y: last.pixelBounds.maxY + 10)
        }

        // 3. Gap before next question → use midpoint of the gap
        let gap = nextQuestionY - qBounds.maxY
        if gap > 40 {
            return CGPoint(x: centerX, y: qBounds.maxY + gap / 2)
        }

        // 4. Fallback: directly below question block
        return CGPoint(x: centerX, y: qBounds.maxY + 10)
    }

    // MARK: - Coordinate Conversion

    /// Converts VN normalized coordinates (bottom-left origin, 0–1) to macOS screen points.
    /// Both Vision and macOS AppKit use bottom-left origin, so no Y-flip is needed.
    private func imageToScreen(normalizedPoint: CGPoint, imageSize: CGSize) -> CGPoint {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(
            x: normalizedPoint.x * screen.width,
            y: normalizedPoint.y * screen.height
        )
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
