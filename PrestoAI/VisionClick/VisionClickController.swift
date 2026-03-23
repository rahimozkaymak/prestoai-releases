import AppKit
import Vision

class VisionClickController {

    private var originalScreenshot: NSImage?
    private var windowFrame: CGRect = .zero

    private let maxCompressSide: CGFloat = 1568
    private let sonnetModel = "claude-sonnet-4-6"

    /// Unified screen element — text (OCR) or control (AX), with pixel-perfect coordinates.
    struct ScreenElement {
        let label: String
        let center: CGPoint
        let source: String       // "ocr", "ax", "box", "synth"
        let confidence: Float    // OCR confidence (0-1), 1.0 for non-OCR sources
    }

    /// Main entry: Scan (OCR + AX) → Direct match → Sonnet pick → Click
    func executeCommand(_ command: String, targetApp: NSRunningApplication, overlayManager: OverlayManager?, completion: @escaping (Bool, String) -> Void) {
        print("[VisionClick] Command: \(command), target: \(targetApp.localizedName ?? "?")")

        guard let capture = captureScreen(targetApp: targetApp) else {
            completion(false, "Could not capture the screen. Check Screen Recording permission in System Settings.")
            return
        }

        originalScreenshot = capture.image
        windowFrame = capture.windowFrame

        DispatchQueue.main.async { overlayManager?.showLoading() }

        let allElements = parallelScan(image: capture.image, targetApp: targetApp, windowOffset: capture.windowFrame.origin)
        print("[VisionClick] merged: \(allElements.count) elements")

        // 1) Direct keyword match — free, instant, pixel-perfect
        if let hit = directMatch(command: command, elements: allElements) {
            print("[VisionClick] Direct hit: '\(hit.label)' [\(hit.source)] at (\(Int(hit.center.x)),\(Int(hit.center.y)))")
            doClick(at: hit.center, method: "\(hit.source.uppercased()) → \(hit.label)", completion: completion)
            return
        }

        // 2) Sonnet picks from the combined list — 1 API call, pixel-perfect
        if !allElements.isEmpty {
            print("[VisionClick] Sonnet pick from \(allElements.count) elements")
            sonnetPickFromList(command: command, elements: allElements, image: capture.image, completion: completion)
            return
        }

        // 3) No elements found at all
        completion(false, "No clickable elements detected on screen.")
    }

    /// Capture screen and scan all elements (OCR + AX + empty boxes). Used by AutomationController.
    func scanScreen(targetApp: NSRunningApplication) -> (image: NSImage, elements: [ScreenElement])? {
        guard let capture = captureScreen(targetApp: targetApp) else { return nil }
        let allElements = parallelScan(image: capture.image, targetApp: targetApp, windowOffset: capture.windowFrame.origin)
        print("[VisionClick] scanScreen: \(allElements.count) elements")
        return (capture.image, allElements)
    }

    // MARK: - Parallel Scan (OCR + AX concurrent)

    private func parallelScan(image: NSImage, targetApp: NSRunningApplication, windowOffset: CGPoint) -> [ScreenElement] {
        var ocrElements: [ScreenElement] = []
        var axElements: [ScreenElement] = []

        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            ocrElements = self.ocrScan(image: image, offset: windowOffset)
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            axElements = self.axScan(targetApp: targetApp)
            group.leave()
        }

        group.wait()

        // Box scan depends on OCR results (for dedup), runs after
        let boxElements = shouldRunBoxDetection(for: targetApp)
            ? emptyBoxScan(image: image, existingElements: ocrElements, offset: windowOffset)
            : []

        let allElements = mergeElements(ocr: ocrElements, ax: axElements, boxes: boxElements)
        print("[VisionClick] OCR: \(ocrElements.count), AX: \(axElements.count), Boxes: \(boxElements.count)")
        return allElements
    }

    // MARK: - Frame Diff (pixel-sampled similarity)

    /// Compare two screenshots by sampling ~200 pixels on a grid.
    /// Returns 1.0 if identical, 0.0 if completely different.
    static func frameSimilarity(_ a: NSImage, _ b: NSImage) -> Double {
        guard let cgA = a.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cgB = b.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0.0 }

        guard let dataA = cgA.dataProvider?.data as Data?,
              let dataB = cgB.dataProvider?.data as Data? else { return 0.0 }

        let widthA = cgA.width, heightA = cgA.height
        let widthB = cgB.width, heightB = cgB.height

        // Different sizes = different frames
        guard widthA == widthB, heightA == heightB else { return 0.0 }

        let bytesPerPixelA = cgA.bitsPerPixel / 8
        let bytesPerRowA = cgA.bytesPerRow
        let bytesPerPixelB = cgB.bitsPerPixel / 8
        let bytesPerRowB = cgB.bytesPerRow

        let gridSize = 14 // 14x14 = 196 sample points
        let tolerance: Int = 10 // per channel

        var matches = 0
        let totalSamples = gridSize * gridSize

        for row in 0..<gridSize {
            let y = row * heightA / gridSize
            for col in 0..<gridSize {
                let x = col * widthA / gridSize

                let offsetA = y * bytesPerRowA + x * bytesPerPixelA
                let offsetB = y * bytesPerRowB + x * bytesPerPixelB

                guard offsetA + 2 < dataA.count, offsetB + 2 < dataB.count else { continue }

                let rDiff = abs(Int(dataA[offsetA]) - Int(dataB[offsetB]))
                let gDiff = abs(Int(dataA[offsetA + 1]) - Int(dataB[offsetB + 1]))
                let bDiff = abs(Int(dataA[offsetA + 2]) - Int(dataB[offsetB + 2]))

                if rDiff <= tolerance && gDiff <= tolerance && bDiff <= tolerance {
                    matches += 1
                }
            }
        }

        return Double(matches) / Double(totalSamples)
    }

    // MARK: - Click Helper

    private func doClick(at point: CGPoint, method: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.main.async {
            ClickExecutor.click(at: point)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion(true, method)
            }
        }
    }

    // MARK: - OCR Scan (text on screen)

    private func ocrScan(image: NSImage, offset: CGPoint = .zero) -> [ScreenElement] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let results = request.results else { return [] }

        let w = image.size.width
        let h = image.size.height

        return results.compactMap { obs in
            // Filter low-confidence OCR (garbage text)
            guard obs.confidence >= 0.4 else { return nil }
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let box = obs.boundingBox
            let cx = (box.origin.x + box.width / 2) * w + offset.x
            let cy = (1.0 - box.origin.y - box.height / 2) * h + offset.y
            return ScreenElement(label: candidate.string, center: CGPoint(x: cx, y: cy), source: "ocr", confidence: obs.confidence)
        }
    }

    /// Only run rectangle-based empty box detection for browsers where homework pages live.
    private func shouldRunBoxDetection(for app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        let browserIDs: Set<String> = [
            "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox",
            "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
            "com.operasoftware.Opera", "com.vivaldi.Vivaldi"
        ]
        return browserIDs.contains(bundleID)
    }

    // MARK: - Empty Box Detection (finds empty input rectangles in screenshot)

    private func emptyBoxScan(image: NSImage, existingElements: [ScreenElement], offset: CGPoint = .zero) -> [ScreenElement] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }

        let w = image.size.width
        let h = image.size.height

        let request = VNDetectRectanglesRequest()
        request.minimumSize = 0.01
        request.maximumObservations = 30
        request.minimumConfidence = 0.3
        request.minimumAspectRatio = 0.15
        request.maximumAspectRatio = 0.95

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let results = request.results else { return [] }

        var boxes: [ScreenElement] = []

        for observation in results {
            let bbox = observation.boundingBox
            let boxX = bbox.origin.x * w + offset.x
            let boxY = (1.0 - bbox.origin.y - bbox.height) * h + offset.y
            let boxW = bbox.width * w
            let boxH = bbox.height * h
            let centerX = boxX + boxW / 2
            let centerY = boxY + boxH / 2

            guard boxW > 30, boxW < 300, boxH > 15, boxH < 60 else { continue }

            let hasTextInside = existingElements.contains { el in
                abs(el.center.x - centerX) < boxW / 2 &&
                abs(el.center.y - centerY) < boxH / 2
            }
            if hasTextInside { continue }

            let nearbyLabel = existingElements
                .filter { el in
                    (el.center.y < centerY + 10) &&
                    (el.center.y > centerY - 80) &&
                    abs(el.center.x - centerX) < 300
                }
                .min(by: { a, b in
                    hypot(a.center.x - centerX, a.center.y - centerY) <
                    hypot(b.center.x - centerX, b.center.y - centerY)
                })

            let label = nearbyLabel.map { "Empty answer box (near \($0.label))" } ?? "Empty answer box"

            boxes.append(ScreenElement(
                label: label,
                center: CGPoint(x: centerX, y: centerY),
                source: "box",
                confidence: 1.0
            ))
        }

        if !boxes.isEmpty {
            print("[VisionClick] Found \(boxes.count) empty answer boxes")
        }
        return boxes
    }

    // MARK: - Accessibility Scan (Dock + Menu Bar + Target App)

    private func axScan(targetApp: NSRunningApplication) -> [ScreenElement] {
        var elements: [ScreenElement] = []

        if let dockPid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier {
            let dockApp = AXUIElementCreateApplication(dockPid)
            axCollect(element: dockApp, into: &elements, depth: 0, maxDepth: 5)
        }

        if let menuBarPid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first?.processIdentifier {
            let menuBarApp = AXUIElementCreateApplication(menuBarPid)
            axCollect(element: menuBarApp, into: &elements, depth: 0, maxDepth: 4)
        }

        let targetElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        axCollect(element: targetElement, into: &elements, depth: 0, maxDepth: 8)

        if targetApp.bundleIdentifier != "com.apple.finder" {
            if let finderPid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier {
                let finderApp = AXUIElementCreateApplication(finderPid)
                axCollect(element: finderApp, into: &elements, depth: 0, maxDepth: 5)
            }
        }

        return elements
    }

    private func axCollect(element: AXUIElement, into elements: inout [ScreenElement], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        let interactive: Set<String> = [
            kAXButtonRole, kAXMenuItemRole, kAXMenuButtonRole,
            kAXToolbarRole, kAXImageRole,
            kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole,
            kAXTabGroupRole, kAXStaticTextRole,
            kAXTextFieldRole, kAXTextAreaRole,
            "AXLink", "AXIcon", "AXToolbarButton", "AXMenuBarItem",
            "AXDockItem", "AXMenuItem", "AXComboBox", "AXSearchField"
        ]

        let inputRoles: Set<String> = [
            kAXTextFieldRole, kAXTextAreaRole, "AXComboBox", "AXSearchField"
        ]

        if interactive.contains(role) || role.contains("Button") || role.contains("Item") || role.contains("Icon") || role.contains("Field") || role.contains("Text") {
            if let el = axExtract(from: element, role: role, isInput: inputRoles.contains(role)) {
                elements.append(el)
            }
        }

        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            axCollect(element: child, into: &elements, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private func axExtract(from element: AXUIElement, role: String, isInput: Bool = false) -> ScreenElement? {
        let foundLabel = axStr(element, kAXTitleAttribute)
            ?? axStr(element, kAXDescriptionAttribute)
            ?? axStr(element, kAXHelpAttribute)
            ?? axStr(element, kAXIdentifierAttribute)
            ?? axStr(element, kAXValueAttribute)

        if !isInput {
            guard let foundLabel = foundLabel, !foundLabel.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        guard let posVal = posRef, let sizeVal = sizeRef else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else { return nil }

        guard size.width > 2, size.height > 2, pos.x >= 0, pos.y >= 0 else { return nil }

        let center = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        let roleName = role.replacingOccurrences(of: "AX", with: "")

        let displayLabel: String
        if let lbl = foundLabel, !lbl.trimmingCharacters(in: .whitespaces).isEmpty {
            displayLabel = "\(lbl) [\(roleName)]"
        } else {
            displayLabel = "Input [\(roleName)]"
        }

        return ScreenElement(label: displayLabel, center: center, source: "ax", confidence: 1.0)
    }

    private func axStr(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        let s = ref as? String
        return (s?.isEmpty == false) ? s : nil
    }

    // MARK: - Merge, Deduplicate & Synthesize Input Fields

    private func mergeElements(ocr: [ScreenElement], ax: [ScreenElement], boxes: [ScreenElement] = []) -> [ScreenElement] {
        var merged = ocr

        for axEl in ax {
            let baseLabel = axEl.label.lowercased().components(separatedBy: " [").first ?? ""
            let isDupe = ocr.contains { ocrEl in
                abs(ocrEl.center.x - axEl.center.x) < 40 &&
                abs(ocrEl.center.y - axEl.center.y) < 40 &&
                ocrEl.label.lowercased().contains(baseLabel)
            }
            if !isDupe {
                merged.append(axEl)
            }
        }

        var synthetic: [ScreenElement] = []
        for ocrEl in ocr {
            let text = ocrEl.label.trimmingCharacters(in: .whitespaces)
            let isInputLabel = text.hasSuffix("=") ||
                (text.count <= 5 && text.contains("=")) ||
                (text.count <= 15 && text.hasSuffix(":"))

            guard isInputLabel else { continue }

            let hasNearbyInput = merged.contains { el in
                el.source == "ax" &&
                el.label.contains("Input") &&
                el.center.x > ocrEl.center.x &&
                el.center.x - ocrEl.center.x < 150 &&
                abs(el.center.y - ocrEl.center.y) < 30
            }

            if !hasNearbyInput {
                let inputCenter = CGPoint(x: ocrEl.center.x + 60, y: ocrEl.center.y)
                let cleanLabel = text.replacingOccurrences(of: "=", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
                synthetic.append(ScreenElement(
                    label: "Input box for \(cleanLabel) [TextField]",
                    center: inputCenter,
                    source: "synth",
                    confidence: 1.0
                ))
            }
        }

        merged.append(contentsOf: synthetic)
        if !synthetic.isEmpty {
            print("[VisionClick] Synthesized \(synthetic.count) input fields from labels")
        }

        for box in boxes {
            let isDupe = merged.contains { el in
                abs(el.center.x - box.center.x) < 40 &&
                abs(el.center.y - box.center.y) < 30
            }
            if !isDupe {
                merged.append(box)
            }
        }

        return merged
    }

    // MARK: - Direct Keyword Match (free, no API call)

    private func directMatch(command: String, elements: [ScreenElement]) -> ScreenElement? {
        let skipWords: Set<String> = [
            "click", "press", "tap", "the", "button", "link", "icon", "menu",
            "tab", "on", "that", "this", "open", "select", "find", "hit", "go", "to"
        ]
        let keywords = command.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !skipWords.contains($0) }

        guard !keywords.isEmpty else { return nil }

        var best: (element: ScreenElement, score: Int)?

        for el in elements {
            let text = el.label.lowercased()
            var score = 0
            for kw in keywords {
                if text.contains(kw) { score += kw.count }
            }
            let baseLabel = text.components(separatedBy: " [").first ?? text
            if keywords.count == 1 && baseLabel == keywords[0] { score += 10 }

            if score > 0 && (best == nil || score > best!.score) {
                best = (el, score)
            }
        }

        return best?.element
    }

    // MARK: - Element List Builder (with region + context + confidence)

    func buildElementList(elements: [ScreenElement]) -> String {
        let screenH = NSScreen.main?.frame.height ?? 900
        let dockY = screenH - 60

        let answerSources: Set<String> = ["box", "synth"]

        var list = ""
        for (i, el) in elements.enumerated() {
            let region: String
            if el.center.y < 30 {
                region = "menu bar"
            } else if el.center.y > dockY {
                region = "dock"
            } else {
                region = "app window"
            }

            // Low-confidence OCR warning
            let confWarning = (el.source == "ocr" && el.confidence < 0.7) ? " ⚠️" : ""

            if answerSources.contains(el.source) || el.label.contains("Input [") {
                let contextAbove = elements.filter { other in
                    other.source == "ocr" &&
                    other.center.y < el.center.y + 10 &&
                    other.center.y > el.center.y - 200 &&
                    abs(other.center.x - el.center.x) < 400
                }
                .sorted { $0.center.y < $1.center.y }
                .map { $0.label }

                let contextLeft = elements.filter { other in
                    other.source == "ocr" &&
                    other.center.x < el.center.x &&
                    el.center.x - other.center.x < 60 &&
                    abs(other.center.y - el.center.y) < 20
                }
                .sorted { $0.center.x < $1.center.x }
                .map { $0.label }

                let contextRight = elements.filter { other in
                    other.source == "ocr" &&
                    other.center.x > el.center.x &&
                    other.center.x - el.center.x < 60 &&
                    abs(other.center.y - el.center.y) < 20
                }
                .sorted { $0.center.x < $1.center.x }
                .map { $0.label }

                var contextParts: [String] = []
                if !contextAbove.isEmpty { contextParts.append("above: \(contextAbove.joined(separator: " | "))") }
                if !contextLeft.isEmpty { contextParts.append("left: \(contextLeft.joined(separator: ", "))") }
                if !contextRight.isEmpty { contextParts.append("right: \(contextRight.joined(separator: ", "))") }

                let contextStr = contextParts.isEmpty ? "" : " — \(contextParts.joined(separator: "; "))"
                list += "[\(i + 1)] \"\(el.label)\"\(confWarning) [\(region)] (\(el.source), y=\(Int(el.center.y)))\(contextStr)\n"
            } else {
                let nearby = elements.filter { other in
                    other.label != el.label &&
                    abs(other.center.y - el.center.y) < 50 &&
                    abs(other.center.x - el.center.x) < 300
                }.prefix(2).map { $0.label }

                let nearbyStr = nearby.isEmpty ? "" : " — near: \(nearby.joined(separator: ", "))"
                list += "[\(i + 1)] \"\(el.label)\"\(confWarning) [\(region)] (\(el.source), y=\(Int(el.center.y)))\(nearbyStr)\n"
            }
        }
        return list
    }

    // MARK: - Sonnet Pick from List

    private func sonnetPickFromList(command: String, elements: [ScreenElement], image: NSImage, completion: @escaping (Bool, String) -> Void) {
        let list = buildElementList(elements: elements)

        guard let base64 = imageToBase64JPEG(image) else {
            completion(false, "Failed to encode screenshot.")
            return
        }

        let prompt = """
        CLICK TASK. The user wants to: \(command)

        Detected elements (with region, position, and nearby context):
        \(list)
        Pick the BEST element to click.

        RULES:
        - Prefer elements in [app window] over [menu bar] or [dock] unless the user specifically asks for menu/dock items.
        - Use y-position and nearby context to disambiguate duplicates.
        - For interactive targets (search bar, input field, button), pick the actual UI control, not a label/title with the same name.
        - IMPORTANT: When clicking a text input field, click the INPUT BOX element (e.g. [TextField], [TextArea], [Group]), NOT the label text next to it (e.g. "R =", "Name:"). The input box is usually the element near the label with a similar y-position.
        - When in doubt, pick the element that is most actionable (e.g. a button or input, not a static heading).

        Respond exactly: PICK:number
        If nothing matches: NOTFOUND:reason
        Nothing else.
        """

        callClaudeWithImage(base64Image: base64, prompt: prompt, model: sonnetModel) { [weak self] response in
            guard let self = self else { return }
            print("[VisionClick] Sonnet pick: \(response)")

            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            if let range = trimmed.range(of: "PICK:", options: .caseInsensitive) {
                let numStr = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let num = Int(numStr), num >= 1, num <= elements.count {
                    let picked = elements[num - 1]
                    self.doClick(at: picked.center, method: "\(picked.source.uppercased())+Sonnet → \(picked.label)", completion: completion)
                    return
                }
            }

            let reason = response.contains("NOTFOUND:")
                ? String(response.split(separator: ":").dropFirst().joined(separator: ":"))
                : "Could not find that element."
            completion(false, reason)
        }
    }

    // MARK: - Screen Capture (window-first, full-screen fallback)

    private func captureScreen(targetApp: NSRunningApplication) -> (image: NSImage, windowFrame: CGRect)? {
        if !CGPreflightScreenCaptureAccess() {
            print("[VisionClick] Screen Recording permission not granted — requesting")
            CGRequestScreenCaptureAccess()
            return nil
        }

        // Try window-only capture first (smaller image, less noise)
        if let windowCapture = captureTargetWindow(targetApp: targetApp) {
            return windowCapture
        }

        // Fallback to full screen
        return captureFullScreen()
    }

    private func captureTargetWindow(targetApp: NSRunningApplication) -> (image: NSImage, windowFrame: CGRect)? {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        // Find the main window of the target app
        let appWindows = windowList.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == targetApp.processIdentifier &&
            ($0[kCGWindowLayer as String] as? Int) == 0 &&
            ($0[kCGWindowAlpha as String] as? Double ?? 0) > 0
        }.sorted { a, b in
            // Prefer larger windows (main window)
            let aW = (a[kCGWindowBounds as String] as? [String: CGFloat])?["Width"] ?? 0
            let bW = (b[kCGWindowBounds as String] as? [String: CGFloat])?["Width"] ?? 0
            return aW > bW
        }

        guard let mainWindow = appWindows.first,
              let boundsDict = mainWindow[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"], let y = boundsDict["Y"],
              let w = boundsDict["Width"], let h = boundsDict["Height"],
              w > 100, h > 100 else {
            return nil
        }

        let windowRect = CGRect(x: x, y: y, width: w, height: h)

        guard let cgImage = CGWindowListCreateImage(windowRect, .optionOnScreenBelowWindow, kCGNullWindowID, [.bestResolution]) else {
            return nil
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        print("[VisionClick] Captured window: \(Int(w))x\(Int(h)) at (\(Int(x)),\(Int(y)))")
        return (nsImage, windowRect)
    }

    private func captureFullScreen(showCursor: Bool = false) -> (image: NSImage, windowFrame: CGRect)? {
        guard let screen = NSScreen.main else { return nil }
        let screenFrame = screen.frame

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("presto_vc_\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
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
            let captureFrame = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
            print("[VisionClick] Captured full screen: \(Int(nsImage.size.width))x\(Int(nsImage.size.height))")
            return (nsImage, captureFrame)
        } catch {
            print("[VisionClick] screencapture error: \(error)")
            return nil
        }
    }

    // MARK: - Claude API

    private func callClaudeWithImage(base64Image: String, prompt: String, model: String? = nil, skipCompression: Bool = false, completion: @escaping (String) -> Void) {
        var fullResponse = ""

        APIService.shared.sendScreenshot(
            base64Image,
            prompt: prompt,
            model: model,
            skipCompression: skipCompression,
            onChunk: { chunk in fullResponse += chunk },
            onComplete: { _, _ in
                let trimmed = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[VisionClick] API response: \(trimmed.prefix(100))")
                completion(trimmed)
            },
            onError: { error in
                print("[VisionClick] API error: \(error.localizedDescription)")
                completion("NOTFOUND:\(error.localizedDescription)")
            }
        )
    }

    // MARK: - Image Encoding

    func imageToBase64JPEG(_ image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return jpeg.base64EncodedString()
    }
}
