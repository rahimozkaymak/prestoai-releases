import AppKit
import ScreenCaptureKit

/// Captures the frontmost window and composites numbered badges onto it.
final class AccessibilityOverlay {

    private static let badgeRadius: CGFloat = 12
    private static let badgeColor = NSColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 0.92)

    // MARK: - Capture frontmost window

    /// Captures the specified app's frontmost window. Uses ScreenCaptureKit on macOS 14+, falls back to screencapture CLI.
    static func captureFrontmostWindow(for app: NSRunningApplication) async -> (image: NSImage, windowFrame: CGRect)? {
        if #available(macOS 14.0, *) {
            return await captureFrontmostWindowSCK(for: app)
        } else {
            return await captureFrontmostWindowCLI(for: app)
        }
    }

    // MARK: - ScreenCaptureKit path (macOS 14+)

    @available(macOS 14.0, *)
    private static func captureFrontmostWindowSCK(for frontApp: NSRunningApplication) async -> (image: NSImage, windowFrame: CGRect)? {

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let scWindow = content.windows.first(where: {
                $0.owningApplication?.processID == frontApp.processIdentifier
                && $0.frame.width > 50 && $0.frame.height > 50
                && $0.isOnScreen
            }) else { return nil }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = Int(scWindow.frame.width * 2)   // Retina
            config.height = Int(scWindow.frame.height * 2)
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let nsImage = NSImage(cgImage: cgImage, size: scWindow.frame.size)
            return (nsImage, scWindow.frame)
        } catch {
            print("[AccessibilityOverlay] ScreenCaptureKit error: \(error)")
            return nil
        }
    }

    // MARK: - CLI fallback (macOS 12-13)

    private static func captureFrontmostWindowCLI(for frontApp: NSRunningApplication) async -> (image: NSImage, windowFrame: CGRect)? {

        // Get window info to find the window ID and bounds
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var targetWindowID: CGWindowID = 0
        var windowBounds = CGRect.zero
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == frontApp.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }

            let bounds = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            if bounds.width > 50 && bounds.height > 50 {
                targetWindowID = wid
                windowBounds = bounds
                break
            }
        }

        guard targetWindowID != 0 else { return nil }

        // Use screencapture CLI with -l flag to capture a specific window
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("presto_ax_\(UUID().uuidString).png")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-l\(targetWindowID)", "-x", tempURL.path]

                do {
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0,
                          let nsImage = NSImage(contentsOf: tempURL) else {
                        try? FileManager.default.removeItem(at: tempURL)
                        continuation.resume(returning: nil)
                        return
                    }

                    try? FileManager.default.removeItem(at: tempURL)
                    continuation.resume(returning: (nsImage, windowBounds))
                } catch {
                    print("[AccessibilityOverlay] screencapture error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Badge compositing

    /// Draws numbered badges on the image at each element's position.
    /// Returns the composited image and a base64 PNG string for the overlay.
    static func compositeBadges(on image: NSImage, windowFrame: CGRect, elements: [ScannedElement]) -> (image: NSImage, base64PNG: String)? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let result = NSImage(size: size)
        result.lockFocus()

        // Draw the original screenshot
        image.draw(in: NSRect(origin: .zero, size: size))

        // Draw badges
        let r = badgeRadius
        for el in elements {
            // Convert screen coordinates to image-local coordinates
            // Screen coords: origin top-left (Quartz), NSImage: origin bottom-left
            let localX = el.position.x - windowFrame.origin.x
            let localY = el.position.y - windowFrame.origin.y
            // Flip Y: image is drawn with origin at bottom-left
            let flippedY = size.height - localY - r

            let badgeRect = NSRect(x: localX - r / 2, y: flippedY - r / 2, width: r * 2, height: r * 2)

            // Circle
            let path = NSBezierPath(ovalIn: badgeRect)
            badgeColor.setFill()
            path.fill()

            // White border
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.5
            path.stroke()

            // Number text
            let text = "\(el.index)" as NSString
            let font = NSFont.systemFont(ofSize: r * 0.9, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let textSize = text.size(withAttributes: attrs)
            let textOrigin = NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            )
            text.draw(at: textOrigin, withAttributes: attrs)
        }

        result.unlockFocus()

        // Convert to base64 PNG
        guard let tiff = result.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }

        let base64 = png.base64EncodedString()
        return (result, base64)
    }
}
