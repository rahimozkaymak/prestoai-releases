import AppKit
import Combine

class AutoSolveManager {

    static let shared = AutoSolveManager()

    enum State {
        case idle
        case scanning
        case analyzing
        case displaying
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isActive: Bool = false

    private var captureTimer: Timer?
    private var captureTask: Task<Void, Never>?
    private var previousScreenshot: NSImage?
    private var sessionId: String = ""
    private var homeworkAccepted = false

    private let captureInterval: TimeInterval = 5.0
    private let changeThreshold: Double = 0.85
    private var backoffSeconds: TimeInterval = 0
    private let maxBackoff: TimeInterval = 120

    var onDeactivated: (() -> Void)?
    var onAnswersReady: (([APIService.AutoSolveAnswer]) -> Void)?

    private let cornerBox = CornerStatusBox.shared

    private init() {
        cornerBox.onAutoSolveAccept = { [weak self] in
            self?.homeworkAccepted = true
            self?.resumeScanning()
        }
        cornerBox.onAutoSolveDecline = { [weak self] in
            self?.deactivate()
        }
        cornerBox.onDismissedAnswer = { [weak self] in
            self?.resumeScanning()
        }
    }

    // MARK: - Lifecycle

    func activate() {
        guard !isActive else { return }
        isActive = true
        sessionId = UUID().uuidString
        homeworkAccepted = false
        previousScreenshot = nil
        state = .scanning
        startCaptureTimer()
        print("[AutoSolve] Activated, session: \(sessionId)")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        state = .idle
        captureTask?.cancel()
        captureTask = nil
        stopCaptureTimer()
        isRequestInFlight = false
        cornerBox.hide()
        previousScreenshot = nil
        homeworkAccepted = false
        onDeactivated?()
        print("[AutoSolve] Deactivated — all timers cancelled")
    }

    func togglePause() {
        if state == .scanning {
            stopCaptureTimer()
            state = .idle
        } else if state == .idle && isActive {
            state = .scanning
            startCaptureTimer()
        }
    }

    private func resumeScanning() {
        guard isActive else { return }
        state = .scanning
        startCaptureTimer()
    }

    // MARK: - Capture Timer

    private func startCaptureTimer() {
        stopCaptureTimer()
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            self?.captureAndCompare()
        }
    }

    private func stopCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = nil
    }

    // MARK: - Capture & Compare

    private var isRequestInFlight = false

    private func captureAndCompare() {
        guard isActive, state == .scanning, !isRequestInFlight else { return }

        captureTask?.cancel()
        captureTask = Task { @MainActor in
            guard isActive else { return }
            guard let base64 = await captureScreen() else { return }
            guard isActive else { return }

            guard let data = Data(base64Encoded: base64),
                  let currentImage = NSImage(data: data) else { return }

            if let prev = previousScreenshot {
                let similarity = VisionClickController.frameSimilarity(prev, currentImage)
                print("[AutoSolve] Frame similarity: \(String(format: "%.1f%%", similarity * 100))")

                if similarity >= changeThreshold {
                    return
                }
            }

            guard isActive else { return }
            previousScreenshot = currentImage

            state = .analyzing
            isRequestInFlight = true
            stopCaptureTimer()

            let (compressed, mediaType) = ImageCompressor.compressForStudy(base64)
            let mode = homeworkAccepted ? "solve" : "detect"
            let deviceId = AppStateManager.shared.deviceID

            do {
                let response = try await APIService.shared.analyzeAutoSolve(
                    image: compressed,
                    mediaType: mediaType,
                    mode: mode,
                    sessionId: sessionId,
                    deviceId: deviceId
                )

                isRequestInFlight = false
                guard isActive else { return }
                backoffSeconds = 0
                handleResponse(response)
            } catch {
                isRequestInFlight = false
                print("[AutoSolve] API error: \(error.localizedDescription)")
                resumeScanning()
            }
        }
    }

    // MARK: - Handle API Response

    private func handleResponse(_ response: APIService.AutoSolveResponse) {
        print("[AutoSolve] Received response: isHomework=\(response.isHomework) answers=\(response.answers.count)")
        if !homeworkAccepted {
            if response.isHomework, let subject = response.subject {
                state = .displaying
                cornerBox.showSuggestion(subject: subject)
            } else {
                resumeScanning()
            }
        } else {
            if response.answers.isEmpty {
                resumeScanning()
            } else {
                state = .displaying
                print("[AutoSolve] Displaying \(response.answers.count) answer\(response.answers.count == 1 ? "" : "s") in overlay")
                onAnswersReady?(response.answers)
            }
        }
    }

    // MARK: - Screen Capture

    private func captureScreen() async -> String? {
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

                continuation.resume(returning: pngData.base64EncodedString())
            }
        }
    }
}
