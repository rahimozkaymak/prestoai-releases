import AppKit
import ScreenCaptureKit

class VisionClickController {

    private var originalScreenshot: NSImage?
    private var windowFrame: CGRect = .zero  // Window frame in screen coordinates (top-left origin, points)

    /// The full two-pass vision click flow.
    func executeCommand(_ command: String, targetApp: NSRunningApplication, overlayManager: OverlayManager?, completion: @escaping (Bool, String) -> Void) {
        print("[VisionClick] Command: \(command), target: \(targetApp.localizedName ?? "?")")

        // Step 1: Capture the full screen
        guard let capture = captureFullScreen() else {
            completion(false, "Could not capture the screen. Check Screen Recording permission in System Settings.")
            return
        }

        originalScreenshot = capture.image
        windowFrame = capture.windowFrame
        print("[VisionClick] Captured window: \(Int(windowFrame.width))x\(Int(windowFrame.height)) at (\(Int(windowFrame.origin.x)),\(Int(windowFrame.origin.y)))")

        // Step 2: Apply coarse grid
        let griddedImage = GridOverlay.applyGrid(to: capture.image)
        guard let griddedBase64 = imageToBase64JPEG(griddedImage) else {
            completion(false, "Failed to encode screenshot.")
            return
        }

        // Step 3: Show loading in overlay
        DispatchQueue.main.async { overlayManager?.showLoading() }

        // Step 4: First API call — coarse pass
        let coarsePrompt = """
        IMPORTANT: You are in GRID CLICK MODE. The screenshot has a coordinate grid overlaid.
        Columns are labeled A, B, C... across the top. Rows are labeled 1, 2, 3... down the left side.

        The user wants to: \(command)

        Find the UI element on screen and respond with ONLY the grid cell where its CENTER is.
        Your ENTIRE response must be exactly in this format, nothing else:
        CELL:G4

        If you truly cannot find it, respond with exactly:
        NOTFOUND:brief reason

        Do NOT explain anything. Just output CELL:XX or NOTFOUND:reason.
        """

        callClaudeWithImage(base64Image: griddedBase64, prompt: coarsePrompt) { [weak self] coarseResponse in
            guard let self = self else { return }
            print("[VisionClick] Coarse response: \(coarseResponse)")

            guard let coarseCell = self.parseCoarseResponse(coarseResponse) else {
                DispatchQueue.main.async {
                    let reason = coarseResponse.contains("NOTFOUND:") ?
                        String(coarseResponse.split(separator: ":").dropFirst().joined(separator: ":")) :
                        "Could not find that element. Try describing it differently."
                    completion(false, reason)
                }
                return
            }

            let coarseCenter = GridOverlay.centerPoint(column: coarseCell.column, row: coarseCell.row)
            print("[VisionClick] Coarse center: \(coarseCenter) (cell \(coarseCell.column)\(coarseCell.row))")

            // Step 5: Zoom pass
            guard let original = self.originalScreenshot,
                  let zoom = ZoomCrop.zoomAroundPoint(image: original, coarseCenter: coarseCenter) else {
                DispatchQueue.main.async { completion(false, "Failed to zoom into the target area.") }
                return
            }

            guard let zoomedBase64 = self.imageToBase64JPEG(zoom.zoomedImage) else {
                DispatchQueue.main.async { completion(false, "Failed to encode zoomed image.") }
                return
            }

            // Step 6: Second API call — fine pass
            let finePrompt = """
            IMPORTANT: You are in PRECISION CLICK MODE. This is a zoomed-in view of a UI element.
            The image has a fine coordinate grid. Columns are labeled 1-20 across the top.
            Rows are labeled 1-20 down the left side.

            Find the exact CENTER of the clickable element and respond with ONLY the grid coordinates.
            Your ENTIRE response must be exactly in this format, nothing else:
            CELL:12,8

            (That means column,row — both are numbers.)
            If the element is not visible, respond with exactly:
            NOTFOUND:brief reason

            Do NOT explain anything. Just output CELL:col,row or NOTFOUND:reason.
            """

            self.callClaudeWithImage(base64Image: zoomedBase64, prompt: finePrompt) { fineResponse in
                print("[VisionClick] Fine response: \(fineResponse)")

                guard let fineCell = self.parseFineResponse(fineResponse) else {
                    DispatchQueue.main.async {
                        let reason = fineResponse.contains("NOTFOUND:") ?
                            String(fineResponse.split(separator: ":").dropFirst().joined(separator: ":")) :
                            "Could not precisely locate the element."
                        completion(false, reason)
                    }
                    return
                }

                // Step 7: Map to screen coordinates
                let preciseImagePoint = ZoomCrop.mapToScreenCoordinates(
                    fineColumn: fineCell.column,
                    fineRow: fineCell.row,
                    cropOrigin: zoom.cropOrigin
                )

                // Convert image pixels → screen points
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let screenX = self.windowFrame.origin.x + preciseImagePoint.x / scale
                let screenY = self.windowFrame.origin.y + preciseImagePoint.y / scale
                let screenPoint = CGPoint(x: screenX, y: screenY)

                print("[VisionClick] Clicking at screen point: (\(Int(screenX)), \(Int(screenY)))")

                // Step 8: Highlight and click
                DispatchQueue.main.async {
                    ClickExecutor.click(at: screenPoint, highlight: true, highlightDuration: 0.4)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        completion(true, "Clicked at (\(Int(screenX)), \(Int(screenY)))")
                    }
                }
            }
        }
    }

    // MARK: - Window Capture

    private func captureFullScreen() -> (image: NSImage, windowFrame: CGRect)? {
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
        process.arguments = ["-x", tempURL.path]  // full screen, no sound

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
