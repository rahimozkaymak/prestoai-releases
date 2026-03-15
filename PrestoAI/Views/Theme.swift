import SwiftUI
import AppKit

enum Theme {
    // MARK: - Backgrounds
    static func bg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.039, green: 0.039, blue: 0.039)
                        : Color(red: 0.98, green: 0.98, blue: 0.98)
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.110, green: 0.110, blue: 0.110)
                        : Color(red: 0.95, green: 0.95, blue: 0.95)
    }
    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.165, green: 0.165, blue: 0.165)
                        : Color(red: 0.85, green: 0.85, blue: 0.85)
    }

    // MARK: - Text
    static func text1(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.878, green: 0.878, blue: 0.878)
                        : Color(red: 0.10, green: 0.10, blue: 0.10)
    }
    static func text2(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.467, green: 0.467, blue: 0.467)
                        : Color(red: 0.45, green: 0.45, blue: 0.45)
    }
    static func text3(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.333, green: 0.333, blue: 0.333)
                        : Color(red: 0.60, green: 0.60, blue: 0.60)
    }
    static func text4(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.400, green: 0.400, blue: 0.400)
                        : Color(red: 0.55, green: 0.55, blue: 0.55)
    }
    static func textDot(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.533, green: 0.533, blue: 0.533)
                        : Color(red: 0.50, green: 0.50, blue: 0.50)
    }

    // MARK: - Keys (setup wizard)
    static func keyBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.133, green: 0.133, blue: 0.133)
                        : Color(red: 0.92, green: 0.92, blue: 0.92)
    }
    static func keyBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.200, green: 0.200, blue: 0.200)
                        : Color(red: 0.80, green: 0.80, blue: 0.80)
    }
    static func keyActive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.180, green: 0.180, blue: 0.180)
                        : Color(red: 0.88, green: 0.88, blue: 0.88)
    }
    static func keyFlash(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.220, green: 0.220, blue: 0.220)
                        : Color(red: 0.85, green: 0.85, blue: 0.85)
    }
    static func keyText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.867)
                        : Color(white: 0.20)
    }
    static func keyTextDim(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.6)
                        : Color(white: 0.45)
    }

    // MARK: - Subtle overlays (buttons, inputs, dividers)
    static func subtleBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }
    static func subtleBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    static func inputBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    // MARK: - Glow/shadow
    static func glowColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
    static func shadowColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.6) : Color.black.opacity(0.15)
    }

    // MARK: - NSColor versions for AppKit panels/windows
    static func nsBg(_ appearance: NSAppearance?) -> NSColor {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1.0)
                      : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
    }
    static func nsOverlayBg(_ appearance: NSAppearance?) -> NSColor {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0.07, green: 0.07, blue: 0.078, alpha: 0.80)
                      : NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.80)
    }

    // MARK: - Helper
    static func isDark(_ appearance: NSAppearance?) -> Bool {
        appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
