import Foundation
import ServiceManagement

/// Wraps SMAppService (macOS 13+) for launch-at-login.
/// No helper bundle needed — registers the main app directly.
/// macOS automatically surfaces it in System Settings → General → Login Items.
class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    private init() {}

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Call once during setup wizard completion. Silent — no UI prompt.
    func enable() {
        guard !isEnabled else { return }
        do {
            try SMAppService.mainApp.register()
            print("[LaunchAtLogin] Registered — will launch at login")
        } catch {
            print("[LaunchAtLogin] Register failed: \(error)")
        }
    }

    func disable() {
        guard isEnabled else { return }
        do {
            try SMAppService.mainApp.unregister()
            print("[LaunchAtLogin] Unregistered")
        } catch {
            print("[LaunchAtLogin] Unregister failed: \(error)")
        }
    }

    func toggle() {
        isEnabled ? disable() : enable()
    }
}
