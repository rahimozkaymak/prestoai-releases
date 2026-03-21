import AppKit
import ScreenCaptureKit

class VisionClickController {

    private var originalScreenshot: NSImage?
    private var windowFrame: CGRect = .zero  // Window frame in screen coordinates (top-left origin, points)

    /// Direct coordinate approach — ask Claude for pixel coordinates, then verify.
    func executeCommand(_ command: String, targetApp: NSRunningApplication, overlayManager: OverlayManager?, completion: @escaping (Bool, String) -> Void) {
        print("[VisionClick] Command: \(command), target: \(targetApp.localizedName ?? "?")")

        // Step 1: Capture the full screen
        guard let capture = captureFullScreen() else {
            completion(false, "Could not capture the screen. Check Screen Recording permission in System Settings.")
            return
        }

        originalScreenshot = capture.image
        windowFrame = capture.windowFrame
        let screenW = capture.image.size.width
        let screenH = capture.image.size.height
        // ImageCompressor resizes to 1024px max side — compute what Claude actually sees
        let maxSide: CGFloat = 1024
        let compressScale = (screenW > screenH)
            ? maxSide / screenW
            : maxSide / screenH
        let claudeW = Int(screenW * compressScale)
        let claudeH = Int(screenH * compressScale)
        print("[VisionClick] Screen: \(Int(screenW))x\(Int(screenH)), Claude sees: \(claudeW)x\(claudeH), scale: \(1.0/compressScale)")

        guard let base64 = imageToBase64JPEG(capture.image) else {
            completion(false, "Failed to encode screenshot.")
            return
        }

        // Step 2: Show loading
        DispatchQueue.main.async { overlayManager?.showLoading() }

        // Step 3: Ask Claude for pixel coordinates in the COMPRESSED image dimensions
        let prompt = """
        CLICK TASK. This screenshot is \(claudeW)x\(claudeH) pixels. Origin is top-left corner (0,0).

        The user wants to: \(command)

        Find the CENTER of that UI element and respond with ONLY its pixel coordinates.
        Your ENTIRE response must be exactly: CLICK:x,y
        Example: CLICK:350,490

        If you cannot find it: NOTFOUND:brief reason
        Nothing else. Just CLICK:x,y or NOTFOUND:reason.
        """

        // Store the scale factor for converting Claude's coords back to screen coords
        let coordScale = 1.0 / compressScale

        callClaudeWithImage(base64Image: base64, prompt: prompt) { [weak self] response in
            guard let self = self else { return }
            print("[VisionClick] Response: \(response)")

            guard let coords = self.parseClickResponse(response) else {
                DispatchQueue.main.async {
                    let reason = response.contains("NOTFOUND:") ?
                        String(response.split(separator: ":").dropFirst().joined(separator: ":")) :
                        "Could not find that element. Try describing it differently."
                    completion(false, reason)
                }
                return
            }

            // Scale from compressed image coords → screen coords
            let screenX = coords.x * coordScale
            let screenY = coords.y * coordScale
            let screenPoint = CGPoint(x: screenX, y: screenY)
            print("[VisionClick] Claude coords: (\(Int(coords.x)),\(Int(coords.y))) → screen: (\(Int(screenX)),\(Int(screenY)))")

            // Step 4: Verification loop
            self.verifyAndClick(at: screenPoint, command: command, attempt: 1, completion: completion)
        }
    }

    /// Parse "CLICK:350,490" → (x: 350, y: 490)
    private func parseClickResponse(_ response: String) -> (x: CGFloat, y: CGFloat)? {
        guard let range = response.range(of: "CLICK:", options: .caseInsensitive) else { return nil }
        let coordStr = String(response[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = coordStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2,
              let x = Double(parts[0]),
              let y = Double(parts[1]) else { return nil }
        return (CGFloat(x), CGFloat(y))
    }

    // MARK: - Verification Loop

    private func verifyAndClick(at point: CGPoint, command: String, attempt: Int, completion: @escaping (Bool, String) -> Void) {
        let maxAttempts = 3

        // Move cursor to target (no click yet)
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                           mouseCursorPosition: point, mouseButton: .left)
        move?.post(tap: .cghidEventTap)

        // Wait for cursor to settle, then screenshot with cursor visible
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }

            // Capture screen WITH cursor visible
            guard let verifyCapture = self.captureFullScreen(showCursor: true),
                  let verifyBase64 = self.imageToBase64JPEG(verifyCapture.image) else {
                // Can't verify — just click where we are
                DispatchQueue.main.async {
                    ClickExecutor.click(at: point, highlight: true, highlightDuration: 0.3)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        completion(true, "Clicked at (\(Int(point.x)), \(Int(point.y)))")
                    }
                }
                return
            }

            let verifyPrompt = """
            CURSOR VERIFICATION: The mouse cursor is now visible on screen.
            The user wanted to: \(command)

            Is the cursor positioned on or very close to the correct element?

            If YES (cursor is on or touching the target): respond exactly CONFIRM
            If NO (cursor is NOT on the target): respond exactly ADJUST:dx,dy
            where dx is pixels to move right (negative=left) and dy is pixels to move down (negative=up).
            Estimate the adjustment needed to reach the CENTER of the target element.

            Examples: ADJUST:50,-20 means move 50px right and 20px up.
            Do NOT explain. Just CONFIRM or ADJUST:dx,dy.
            """

            self.callClaudeWithImage(base64Image: verifyBase64, prompt: verifyPrompt) { response in
                print("[VisionClick] Verify attempt \(attempt): \(response)")

                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmed.uppercased().contains("CONFIRM") {
                    // Cursor is on target — click!
                    DispatchQueue.main.async {
                        ClickExecutor.click(at: point, highlight: true, highlightDuration: 0.3)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            completion(true, "Clicked at (\(Int(point.x)), \(Int(point.y)))")
                        }
                    }
                } else if let adjustment = self.parseAdjustment(trimmed), attempt < maxAttempts {
                    // Adjust and retry
                    let newPoint = CGPoint(x: point.x + adjustment.dx, y: point.y + adjustment.dy)
                    print("[VisionClick] Adjusting by (\(adjustment.dx), \(adjustment.dy)) → (\(Int(newPoint.x)), \(Int(newPoint.y)))")
                    self.verifyAndClick(at: newPoint, command: command, attempt: attempt + 1, completion: completion)
                } else {
                    // Max attempts or can't parse — click where we are
                    DispatchQueue.main.async {
                        ClickExecutor.click(at: point, highlight: true, highlightDuration: 0.3)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            completion(true, "Clicked at (\(Int(point.x)), \(Int(point.y))) after \(attempt) attempts")
                        }
                    }
                }
            }
        }
    }

    /// Parse "ADJUST:50,-20" → (dx: 50, dy: -20)
    private func parseAdjustment(_ response: String) -> (dx: CGFloat, dy: CGFloat)? {
        guard let range = response.range(of: "ADJUST:", options: .caseInsensitive) else { return nil }
        let coordStr = String(response[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = coordStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2,
              let dx = Double(parts[0]),
              let dy = Double(parts[1]) else { return nil }
        return (CGFloat(dx), CGFloat(dy))
    }

    // MARK: - Screen Capture

    private func captureFullScreen(showCursor: Bool = false) -> (image: NSImage, windowFrame: CGRect)? {
        // Screen Recording permission is required
        if !CGPreflightScreenCaptureAccess() {
            print("[VisionClick] Screen Recording permission not granted — requesting")
            CGRequestScreenCaptureAccess()
            return nil
        }

        guard let screen = NSScreen.main else { return nil }
        let screenFrame = screen.frame

        // Capture the entire screen (no -i flag = non-interactive, no -l = full screen)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("presto_vc_\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -C = capture cursor, -x = no sound
        var args = ["-x"]
        if showCursor { args.append("-C") }
        args.append(tempURL.path)
        process.arguments = args

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  let nsImage = NSImage(contentsOf: tempURL) else {
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            try? FileManager.default.removeItem(at: tempURL)
            // Screen frame for coordinate mapping: origin (0,0), full screen size
            let captureFrame = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
            print("[VisionClick] Captured full screen: \(Int(nsImage.size.width))x\(Int(nsImage.size.height))")
            return (nsImage, captureFrame)
        } catch {
            print("[VisionClick] screencapture error: \(error)")
            return nil
        }
    }

    // MARK: - Claude API Call

    private func callClaudeWithImage(base64Image: String, prompt: String, completion: @escaping (String) -> Void) {
        // Use the existing streaming API and collect all chunks into a single response
        var fullResponse = ""

        APIService.shared.sendScreenshot(
            base64Image,
            prompt: prompt,
            onChunk: { chunk in
                fullResponse += chunk
            },
            onComplete: { _, _ in
                let trimmed = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[VisionClick] API response collected: \(trimmed.prefix(100))")
                completion(trimmed)
            },
            onError: { error in
                print("[VisionClick] API error: \(error.localizedDescription)")
                completion("NOTFOUND:\(error.localizedDescription)")
            }
        )
    }

    // MARK: - Response Parsing

    /// Parse coarse response like "CELL:G4" → (column: "G", row: 4)
    private func parseCoarseResponse(_ response: String) -> (column: String, row: Int)? {
        // Find CELL: pattern anywhere in the response
        guard let range = response.range(of: "CELL:", options: .caseInsensitive) else { return nil }
        let cellRef = String(response[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Split into letters (column) and digits (row)
        var column = ""
        var rowStr = ""
        for ch in cellRef {
            if ch.isLetter {
                if rowStr.isEmpty {
                    column.append(ch)
                } else {
                    break  // letters after digits means we've gone past
                }
            } else if ch.isNumber {
                rowStr.append(ch)
            } else {
                if !column.isEmpty && !rowStr.isEmpty { break }
            }
        }

        guard !column.isEmpty, let row = Int(rowStr), row > 0 else { return nil }
        return (column.uppercased(), row)
    }

    /// Parse fine response like "CELL:12,8" → (column: 12, row: 8)
    private func parseFineResponse(_ response: String) -> (column: Int, row: Int)? {
        guard let range = response.range(of: "CELL:", options: .caseInsensitive) else { return nil }
        let coordStr = String(response[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = coordStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2,
              let col = Int(parts[0]),
              let row = Int(parts[1]),
              col > 0, row > 0 else { return nil }

        return (col, row)
    }

    // MARK: - Image Encoding

    private func imageToBase64JPEG(_ image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return jpeg.base64EncodedString()
    }
}
