import AppKit
import CoreGraphics
import Carbon.HIToolbox

class ClickExecutor {

    // MARK: - Key Code Map

    private static let keyCodeMap: [String: UInt16] = [
        "enter": UInt16(kVK_Return), "return": UInt16(kVK_Return),
        "tab": UInt16(kVK_Tab), "escape": UInt16(kVK_Escape), "esc": UInt16(kVK_Escape),
        "space": UInt16(kVK_Space), "delete": UInt16(kVK_Delete), "backspace": UInt16(kVK_Delete),
        "up": UInt16(kVK_UpArrow), "down": UInt16(kVK_DownArrow),
        "left": UInt16(kVK_LeftArrow), "right": UInt16(kVK_RightArrow),
        "a": UInt16(kVK_ANSI_A), "b": UInt16(kVK_ANSI_B), "c": UInt16(kVK_ANSI_C),
        "d": UInt16(kVK_ANSI_D), "e": UInt16(kVK_ANSI_E), "f": UInt16(kVK_ANSI_F),
        "g": UInt16(kVK_ANSI_G), "h": UInt16(kVK_ANSI_H), "i": UInt16(kVK_ANSI_I),
        "j": UInt16(kVK_ANSI_J), "k": UInt16(kVK_ANSI_K), "l": UInt16(kVK_ANSI_L),
        "m": UInt16(kVK_ANSI_M), "n": UInt16(kVK_ANSI_N), "o": UInt16(kVK_ANSI_O),
        "p": UInt16(kVK_ANSI_P), "q": UInt16(kVK_ANSI_Q), "r": UInt16(kVK_ANSI_R),
        "s": UInt16(kVK_ANSI_S), "t": UInt16(kVK_ANSI_T), "u": UInt16(kVK_ANSI_U),
        "v": UInt16(kVK_ANSI_V), "w": UInt16(kVK_ANSI_W), "x": UInt16(kVK_ANSI_X),
        "y": UInt16(kVK_ANSI_Y), "z": UInt16(kVK_ANSI_Z),
        "0": UInt16(kVK_ANSI_0), "1": UInt16(kVK_ANSI_1), "2": UInt16(kVK_ANSI_2),
        "3": UInt16(kVK_ANSI_3), "4": UInt16(kVK_ANSI_4), "5": UInt16(kVK_ANSI_5),
        "6": UInt16(kVK_ANSI_6), "7": UInt16(kVK_ANSI_7), "8": UInt16(kVK_ANSI_8),
        "9": UInt16(kVK_ANSI_9),
    ]

    /// Press a key combination like "Cmd+V", "Enter", "Tab".
    static func pressKey(_ combo: String) {
        let parts = combo.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        var flags: CGEventFlags = []
        var keyCode: UInt16 = 0
        var foundKey = false

        for part in parts {
            switch part {
            case "cmd", "command":    flags.insert(.maskCommand)
            case "shift":             flags.insert(.maskShift)
            case "option", "alt":     flags.insert(.maskAlternate)
            case "ctrl", "control":   flags.insert(.maskControl)
            default:
                if let code = keyCodeMap[part] {
                    keyCode = code
                    foundKey = true
                }
            }
        }

        guard foundKey else {
            print("[ClickExecutor] Unknown key combo: \(combo)")
            return
        }

        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(50_000)
        up?.post(tap: .cghidEventTap)

        print("[ClickExecutor] Pressed key: \(combo)")
    }

    /// Scroll the screen. Positive = scroll down, negative = scroll up.
    static func scroll(direction: String, amount: Int32 = 5) {
        let delta: Int32
        switch direction.lowercased() {
        case "down":  delta = -amount
        case "up":    delta = amount
        default:      delta = -amount
        }

        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
        print("[ClickExecutor] Scrolled \(direction) (\(amount) lines)")
    }

    // MARK: - Click

    static func click(at point: CGPoint, highlight: Bool = false, highlightDuration: TimeInterval = 0.4) {
        performClick(at: point)
    }

    private static func performClick(at point: CGPoint) {
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                           mouseCursorPosition: point, mouseButton: .left)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        let up   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                           mouseCursorPosition: point, mouseButton: .left)

        move?.post(tap: .cghidEventTap)
        usleep(50_000)
        down?.post(tap: .cghidEventTap)
        usleep(50_000)
        up?.post(tap: .cghidEventTap)

        print("[ClickExecutor] Clicked at (\(Int(point.x)), \(Int(point.y)))")
    }

    // MARK: - Double Click

    static func doubleClick(at point: CGPoint, highlight: Bool = false, highlightDuration: TimeInterval = 0.4) {
        performDoubleClick(at: point)
    }

    private static func performDoubleClick(at point: CGPoint) {
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                           mouseCursorPosition: point, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        usleep(50_000)

        for i in 1...2 {
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                               mouseCursorPosition: point, mouseButton: .left)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                             mouseCursorPosition: point, mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            down?.post(tap: .cghidEventTap)
            usleep(50_000)
            up?.post(tap: .cghidEventTap)
            usleep(50_000)
        }

        print("[ClickExecutor] Double-clicked at (\(Int(point.x)), \(Int(point.y)))")
    }

    // MARK: - Highlight

    private static func showClickHighlight(at point: CGPoint, duration: TimeInterval) {
        DispatchQueue.main.async {
            let diameter: CGFloat = 30
            let screenHeight = NSScreen.main?.frame.height ?? 900
            let flippedY = screenHeight - point.y

            let frame = NSRect(x: point.x - diameter / 2, y: flippedY - diameter / 2,
                               width: diameter, height: diameter)

            let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces]

            let circleView = HighlightCircleView(frame: NSRect(origin: .zero,
                                                                size: NSSize(width: diameter, height: diameter)))
            window.contentView = circleView
            window.orderFront(nil)

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

    // MARK: - Type Text (clipboard paste — works in Electron/web apps)

    static func typeText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        usleep(50_000)
        pressKey("Cmd+V")
        usleep(100_000)

        if let old = oldContents {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }

        print("[ClickExecutor] Pasted text: \(text.prefix(50))")
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
