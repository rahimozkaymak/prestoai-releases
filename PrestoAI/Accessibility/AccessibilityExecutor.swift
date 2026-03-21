import ApplicationServices

/// Performs actions on scanned accessibility elements by index.
final class AccessibilityExecutor {

    /// Stores actual AXUIElement references from the most recent scan.
    private(set) var elementMap: [Int: AXUIElement] = [:]

    /// Update the element map after a new scan.
    func update(map: [Int: AXUIElement]) {
        elementMap = map
    }

    /// Click / press the element at the given index.
    @discardableResult
    func click(elementIndex: Int) -> Bool {
        guard let el = elementMap[elementIndex] else { return false }
        return AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }

    /// Set the text value of a text field at the given index.
    @discardableResult
    func type(elementIndex: Int, text: String) -> Bool {
        guard let el = elementMap[elementIndex] else { return false }
        // Focus first
        AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, true as CFTypeRef)
        let result = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFTypeRef)
        return result == .success
    }

    /// Focus the element at the given index.
    @discardableResult
    func focus(elementIndex: Int) -> Bool {
        guard let el = elementMap[elementIndex] else { return false }
        return AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success
    }

    /// Read the current value of the element at the given index.
    func getValue(elementIndex: Int) -> String? {
        guard let el = elementMap[elementIndex] else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &ref) == .success else { return nil }
        if let s = ref as? String { return s }
        if let n = ref as? NSNumber { return n.stringValue }
        return nil
    }
}
