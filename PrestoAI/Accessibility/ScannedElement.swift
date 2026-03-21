import Foundation

/// Data model for a single interactive UI element found by the accessibility scanner.
struct ScannedElement {
    let index: Int
    let role: String
    let title: String?
    let description: String?
    let value: String?
    let position: CGPoint
    let size: CGSize
    let isEnabled: Bool
    let actions: [String]
    let appName: String

    /// Human-readable summary line, e.g.  [1] Button "Save" (412, 305) 80×32
    var summaryLine: String {
        var parts = "[\(index)] \(role)"
        if let t = title, !t.isEmpty { parts += " \"\(t)\"" }
        if let d = description, !d.isEmpty, d != title { parts += " desc:\"\(d)\"" }
        if let v = value, !v.isEmpty { parts += " value:\"\(v)\"" }
        parts += " (\(Int(position.x)), \(Int(position.y))) \(Int(size.width))x\(Int(size.height))"
        if !isEnabled { parts += " [disabled]" }
        return parts
    }
}
