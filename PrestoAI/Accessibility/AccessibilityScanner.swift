import AppKit
import ApplicationServices

/// Walks the accessibility tree of the frontmost application and returns every interactive element.
final class AccessibilityScanner {

    // Roles we consider interactive / worth surfacing
    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXCheckBox",
        "AXRadioButton", "AXLink", "AXMenuItem", "AXPopUpButton",
        "AXSlider", "AXTab", "AXTabGroup", "AXComboBox",
        "AXScrollBar", "AXToolbar", "AXMenuButton", "AXIncrementor",
        "AXDisclosureTriangle", "AXSwitch", "AXToggle",
        "AXSearchField", "AXSecureTextField", "AXStaticText",
        "AXImage", "AXCell"
    ]

    private static let maxDepth = 15
    private static let timeoutSeconds: TimeInterval = 3.0

    /// Check (and optionally prompt) for Accessibility trust.
    static func isTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }

    // MARK: - Public scan

    /// Scans the given app's accessibility tree on a background queue.
    /// The app must be captured before any UI activation (e.g. showing loading overlay).
    static func scan(app: NSRunningApplication, completion: @escaping ([ScannedElement], [Int: AXUIElement]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let pid = app.processIdentifier
            let appName = app.localizedName ?? "Unknown"
            let axApp = AXUIElementCreateApplication(pid)

            // Debug: check if we can read any attribute from the app element
            var roleRef: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(axApp, kAXRoleAttribute as CFString, &roleRef)
            print("[AccessibilityScanner] App AXRole query result: \(roleResult.rawValue) (0=success), role=\(roleRef as? String ?? "nil")")

            var childrenRef: CFTypeRef?
            let childResult = AXUIElementCopyAttributeValue(axApp, kAXChildrenAttribute as CFString, &childrenRef)
            let childCount = (childrenRef as? [AXUIElement])?.count ?? 0
            print("[AccessibilityScanner] App children query result: \(childResult.rawValue), count=\(childCount)")

            var elements: [ScannedElement] = []
            var elementMap: [Int: AXUIElement] = [:]
            var index = 1
            let deadline = Date().addingTimeInterval(timeoutSeconds)

            walk(element: axApp, appName: appName, depth: 0, deadline: deadline,
                 index: &index, elements: &elements, elementMap: &elementMap)

            print("[AccessibilityScanner] Scan complete: \(elements.count) elements found")
            DispatchQueue.main.async { completion(elements, elementMap) }
        }
    }

    // MARK: - Tree walker

    private static func walk(element: AXUIElement, appName: String, depth: Int, deadline: Date,
                             index: inout Int, elements: inout [ScannedElement],
                             elementMap: inout [Int: AXUIElement]) {
        guard depth < maxDepth, Date() < deadline else { return }

        let role = stringAttr(element, kAXRoleAttribute as CFString) ?? ""
        let isInteractive = interactiveRoles.contains(role)

        if isInteractive {
            let title = stringAttr(element, kAXTitleAttribute as CFString)
            let desc  = stringAttr(element, kAXDescriptionAttribute as CFString)
            let value = valueString(element)
            let pos   = pointAttr(element)
            let size  = sizeAttr(element)
            let enabled = boolAttr(element, kAXEnabledAttribute as CFString)
            let actions = actionNames(element)

            // Skip zero-size or off-screen elements
            if size.width > 0 && size.height > 0 {
                let el = ScannedElement(
                    index: index, role: friendlyRole(role),
                    title: title, description: desc, value: value,
                    position: pos, size: size,
                    isEnabled: enabled, actions: actions,
                    appName: appName
                )
                elements.append(el)
                elementMap[index] = element
                index += 1
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard childResult == .success, let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            walk(element: child, appName: appName, depth: depth + 1, deadline: deadline,
                 index: &index, elements: &elements, elementMap: &elementMap)
        }
    }

    // MARK: - Attribute helpers

    private static func stringAttr(_ el: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func boolAttr(_ el: AXUIElement, _ attr: CFString) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return true }
        if let num = ref as? NSNumber { return num.boolValue }
        return true
    }

    private static func pointAttr(_ el: AXUIElement) -> CGPoint {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &ref) == .success else { return .zero }
        var point = CGPoint.zero
        AXValueGetValue(ref as! AXValue, .cgPoint, &point)
        return point
    }

    private static func sizeAttr(_ el: AXUIElement) -> CGSize {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &ref) == .success else { return .zero }
        var size = CGSize.zero
        AXValueGetValue(ref as! AXValue, .cgSize, &size)
        return size
    }

    private static func valueString(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &ref) == .success else { return nil }
        if let s = ref as? String { return s }
        if let n = ref as? NSNumber { return n.stringValue }
        return nil
    }

    private static func actionNames(_ el: AXUIElement) -> [String] {
        var namesRef: CFArray?
        guard AXUIElementCopyActionNames(el, &namesRef) == .success, let names = namesRef as? [String] else { return [] }
        return names
    }

    /// Strip "AX" prefix for readability
    private static func friendlyRole(_ role: String) -> String {
        if role.hasPrefix("AX") { return String(role.dropFirst(2)) }
        return role
    }
}
