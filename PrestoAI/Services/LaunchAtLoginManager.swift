import Foundation
import ServiceManagement

/// Wraps SMAppService (macOS 13+) for launch-at-login.
/// Falls back to SMLoginItemSetEnabled on macOS 12.
class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    private let legacyKey = "LaunchAtLoginEnabled"
    private init() {}

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return UserDefaults.standard.bool(forKey: legacyKey)
        }
    }

    /// Call once during setup wizard completion. Silent — no UI prompt.
    func enable() {
        guard !isEnabled else { return }
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                print("[LaunchAtLogin] Registered — will launch at login")
            } catch {
                print("[LaunchAtLogin] Register failed: \(error)")
            }
        } else {
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let success = SMLoginItemSetEnabled(bundleID as CFString, true)
            UserDefaults.standard.set(success, forKey: legacyKey)
            print("[LaunchAtLogin] Legacy register: \(success ? "success" : "failed")")
        }
    }

    func disable() {
        guard isEnabled else { return }
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                print("[LaunchAtLogin] Unregistered")
            } catch {
                print("[LaunchAtLogin] Unregister failed: \(error)")
            }
        } else {
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let success = SMLoginItemSetEnabled(bundleID as CFString, false)
            if success { UserDefaults.standard.set(false, forKey: legacyKey) }
            print("[LaunchAtLogin] Legacy unregister: \(success ? "success" : "failed")")
        }
    }

    func toggle() {
        isEnabled ? disable() : enable()
    }
}
