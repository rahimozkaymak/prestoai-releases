import AppKit
import Vision
import CoreGraphics

// MARK: - Content Change Detection

enum ContentChangeResult {
    case unchanged
    case newContent(ocrPreview: String, capturedImage: CGImage, base64: String, isNewPage: Bool)
    case blocked(reason: BlockReason)

    enum BlockReason {
        case privateApp
        case sensitiveWindow
        case sensitiveContent
    }
}

class ContentDetector {
    private var lastContentHash: UInt64 = 0
    private var knownTextFragments: Set<String> = []

    // Structural fallback state
    private var lastStructuralStrip: [UInt8]?

    // MARK: - Public API

    /// Full detection cycle: privacy check → capture → OCR fingerprint → change detection
    func detect(
        privacyFilter: PrivacyFilter,
        sessionMemory: SessionMemory
    ) async -> ContentChangeResult {
        // Privacy gates
        let appName = getCurrentAppName()
        let windowTitle = getCurrentWindowTitle()
        if privacyFilter.isCurrentAppExcluded(appName: appName) {
            return .blocked(reason: .privateApp)
        }
        if privacyFilter.isCurrentWindowSensitive(windowTitle: windowTitle) {
            return .blocked(reason: .sensitiveWindow)
        }

        // Capture screen
        guard let (cgImage, base64) = await captureScreen() else {
            return .unchanged
        }

        // OCR on top 30%
        let topRegion = cropToTopRegion(cgImage, fraction: 0.3)
        let ocrText = await runVisionOCR(topRegion)

        // Sensitive content check
        if privacyFilter.containsSensitiveContent(ocrText) {
            return .blocked(reason: .sensitiveContent)
        }

        return processCapture(image: cgImage, base64: base64, ocrText: ocrText, sessionMemory: sessionMemory)
    }

    /// Lightweight hash-only check (no privacy filter, image already captured)
    func detectContentChange(image: CGImage, base64: String, sessionMemory: SessionMemory) async -> ContentChangeResult {
        let topRegion = cropToTopRegion(image, fraction: 0.3)
        let ocrText = await runVisionOCR(topRegion)
        return processCapture(image: image, base64: base64, ocrText: ocrText, sessionMemory: sessionMemory)
    }

    func reset() {
        lastContentHash = 0
        knownTextFragments = []
        lastStructuralStrip = nil
    }

    func registerKnownFragments(_ fragments: Set<String>) {
        knownTextFragments = fragments
    }

    func addKnownFragments(_ fragments: Set<String>) {
        knownTextFragments.formUnion(fragments)
    }

    // MARK: - Layer 1: Text Fingerprinting

    private func processCapture(image: CGImage, base64: String, ocrText: String, sessionMemory: SessionMemory) -> ContentChangeResult {
        // If OCR returned nothing, try structural fallback
        guard !ocrText.isEmpty else {
            return structuralFallback(image: image, base64: base64)
        }

        let currentHash = stableHash(ocrText)

        if currentHash != lastContentHash {
            lastContentHash = currentHash

            // Determine scroll vs page turn
            let fragments = extractTextFragments(from: ocrText)
            let known = sessionMemory.allQuestionTextFragments()
            let unknownFragments = fragments.subtracting(known)

            let isNewPage: Bool
            if known.isEmpty {
                isNewPage = true
            } else {
                // >50% unknown fragments = new page
                isNewPage = unknownFragments.count > known.count / 2
            }

            return .newContent(
                ocrPreview: ocrText,
                capturedImage: image,
                base64: base64,
                isNewPage: isNewPage
            )
        }

        return .unchanged
    }

    // MARK: - Layer 2: Structural Fallback

    private func structuralFallback(image: CGImage, base64: String) -> ContentChangeResult {
        let strip = sampleStructuralStrip(image)

        guard let previousStrip = lastStructuralStrip else {
            lastStructuralStrip = strip
            return .newContent(ocrPreview: "", capturedImage: image, base64: base64, isNewPage: true)
        }

        let similarity = compareStrips(previousStrip, strip)
        lastStructuralStrip = strip

        if similarity < 0.60 {
            return .newContent(ocrPreview: "", capturedImage: image, base64: base64, isNewPage: true)
        }

        return .unchanged
    }

    /// Sample a 10×20 vertical strip from the left 25% of the screen
    private func sampleStructuralStrip(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data as Data? else { return [] }
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        let cols = 10
        let rows = 20
        let regionWidth = image.width / 4 // left 25%
        var samples: [UInt8] = []
        samples.reserveCapacity(cols * rows * 3)

        for row in 0..<rows {
            let y = row * image.height / rows
            for col in 0..<cols {
                let x = col * regionWidth / cols
                let offset = y * bpr + x * bpp
                guard offset + 2 < data.count else {
                    samples.append(contentsOf: [0, 0, 0])
                    continue
                }
                samples.append(data[offset])
                samples.append(data[offset + 1])
                samples.append(data[offset + 2])
            }
        }
        return samples
    }

    private func compareStrips(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let tolerance = 10
        var matches = 0
        let total = a.count / 3

        for i in stride(from: 0, to: min(a.count, b.count) - 2, by: 3) {
            if abs(Int(a[i]) - Int(b[i])) <= tolerance &&
               abs(Int(a[i+1]) - Int(b[i+1])) <= tolerance &&
               abs(Int(a[i+2]) - Int(b[i+2])) <= tolerance {
                matches += 1
            }
        }

        return Double(matches) / Double(total)
    }

    // MARK: - Vision OCR

    private func runVisionOCR(_ image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                // Take first ~200 chars for fingerprinting
                let preview = String(text.prefix(200))
                continuation.resume(returning: preview)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[ContentDetector] OCR failed: \(error)")
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - Image Helpers

    private func cropToTopRegion(_ image: CGImage, fraction: CGFloat) -> CGImage {
        let cropHeight = Int(CGFloat(image.height) * fraction)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: cropHeight)
        return image.cropping(to: rect) ?? image
    }

    // MARK: - Screen Capture

    func captureScreen() async -> (CGImage, String)? {
        guard CGPreflightScreenCaptureAccess() else {
            print("[ContentDetector] No screen recording permission")
            return nil
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let cg = CGWindowListCreateImage(
                    CGRect.null, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]
                ) else { continuation.resume(returning: nil); return }
                let bmp = NSBitmapImageRep(cgImage: cg)
                guard let png = bmp.representation(using: .png, properties: [:]) else {
                    continuation.resume(returning: nil); return
                }
                continuation.resume(returning: (cg, png.base64EncodedString()))
            }
        }
    }

    // MARK: - Text Fragment Extraction

    private func extractTextFragments(from text: String) -> Set<String> {
        // Split into meaningful fragments (words/short phrases)
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 3 }
            .map { $0.lowercased() }
        return Set(words)
    }

    // MARK: - Hashing

    private func stableHash(_ string: String) -> UInt64 {
        // FNV-1a hash — fast, stable, low collision
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    // MARK: - System Helpers

    private func getCurrentAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    private func getCurrentWindowTitle() -> String {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]],
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return "" }
        return list.first(where: {
            ($0[kCGWindowOwnerPID as String] as? Int32) == pid &&
            ($0[kCGWindowLayer as String] as? Int) == 0
        }).flatMap { $0[kCGWindowName as String] as? String } ?? ""
    }
}
