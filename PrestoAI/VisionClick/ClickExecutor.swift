import AppKit
import CoreGraphics

class ClickExecutor {

    /// Moves the mouse to the target point and performs a click.
    static func click(at point: CGPoint, highlight: Bool = true, highlightDuration: TimeInterval = 0.4) {
        if highlight {
            showClickHighlight(at: point, duration: highlightDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + highlightDuration) {
                performClick(at: point)
            }
        } else {
            performClick(at: point)
        }
    }

    private static func performClick(at point: CGPoint) {
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                           mouseCursorPosition: point, mouseButton: .left)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        let up   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                           mouseCursorPosition: point, mouseButton: .left)

        move?.post(tap: .cghidEventTap)
        usleep(50_000)  // 50ms
        down?.post(tap: .cghidEventTap)
        usleep(50_000)
        up?.post(tap: .cghidEventTap)

        print("[ClickExecutor] Clicked at (\(Int(point.x)), \(Int(point.y)))")
    }

    /// Shows a pulsing red circle at the click target.
    private static func showClickHighlight(at point: CGPoint, duration: TimeInterval) {
        DispatchQueue.main.async {
            let diameter: CGFloat = 30
            // Convert CGEvent screen coords (top-left origin) to NSWindow coords (bottom-left)
            let screenHeight = NSScreen.main?.frame.height ?? 900
            let flippedY = screenHeight - point.y

            let frame = NSRect(
                x: point.x - diameter / 2,
                y: flippedY - diameter / 2,
                width: diameter,
                height: diameter
            )

            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces]

            let circleView = HighlightCircleView(frame: NSRect(origin: .zero,
                                                                size: NSSize(width: diameter, height: diameter)))
            window.contentView = circleView
            window.orderFrontRegardless()

            // Pulse animation
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration * 0.5
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0.3
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration * 0.5
                    window.animator().alphaValue = 1.0
                } completionHandler: {
                    window.orderOut(nil)
                }
            }
        }
    }

    /// Type text using CGEvent key events (foundation for future use).
    static func typeText(_ text: String) {
        for char in text {
            let str = String(char) as NSString
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { continue }
            var uniChar = str.character(at: 0)
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
            event.post(tap: .cghidEventTap)

            let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            upEvent?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
            upEvent?.post(tap: .cghidEventTap)

            usleep(20_000)  // 20ms between keystrokes
        }
    }
}

// MARK: - Highlight circle view

private class HighlightCircleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        NSColor.red.withAlphaComponent(0.5).setFill()
        path.fill()
        NSColor.red.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
