import AppKit
import ScreenCaptureKit

class VisionClickController {

    private var originalScreenshot: NSImage?
    private var windowFrame: CGRect = .zero  // Window frame in screen coordinates (top-left origin, points)

    /// The full two-pass vision click flow.
    func executeCommand(_ command: String, targetApp: NSRunningApplication, overlayManager: OverlayManager?, completion: @escaping (Bool, String) -> Void) {
        print("[VisionClick] Command: \(command), target: \(targetApp.localizedName ?? "?")")

        // Step 1: Capture the target app's window
        guard let capture = captureWindow(for: targetApp) else {
            completion(false, "Could not capture the frontmost window.")
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
        You are a screen interaction assistant. The user wants to interact with an element on screen.
        The screenshot has a coordinate grid overlaid. Columns are labeled A, B, C... across the top.
        Rows are labeled 1, 2, 3... down the left side.
        Identify the UI element the user is referring to and respond with ONLY the grid cell where the CENTER
        of that element is located, in the format: CELL:G4
        If you cannot identify the element, respond with: NOTFOUND:reason

        User command: \(command)
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
            You are a precision click assistant. This is a zoomed-in view of a UI element.
            The image has a fine coordinate grid. Columns are labeled 1-20 across the top.
            Rows are labeled 1-20 down the left side.
            Identify the exact CENTER of the clickable element and respond with ONLY the grid cell
            in the format: CELL:12,8 (column,row)
            If the element is not visible in this zoomed view, respond with: NOTFOUND:reason
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

    private func captureWindow(for app: NSRunningApplication) -> (image: NSImage, windowFrame: CGRect)? {
        let pid = app.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID else { continue }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0
            )
            guard bounds.width > 50 && bounds.height > 50 else { continue }

            // Use screencapture CLI for compatibility (CGWindowListCreateImage is unavailable in newer SDKs)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("presto_vc_\(UUID().uuidString).png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-l\(windowID)", "-x", tempURL.path]

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0,
                      let nsImage = NSImage(contentsOf: tempURL) else {
                    try? FileManager.default.removeItem(at: tempURL)
                    continue
                }

                try? FileManager.default.removeItem(at: tempURL)
                return (nsImage, bounds)
            } catch {
                print("[VisionClick] screencapture error: \(error)")
                continue
            }
        }
        return nil
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
