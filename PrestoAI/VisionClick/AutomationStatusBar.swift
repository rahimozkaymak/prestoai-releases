import AppKit

/// Shows automation status in the macOS menu bar (like WiFi/battery icons).
/// Never steals focus, never overlaps the screen, auto-updates in place.
class AutomationStatusBar {

    private var statusItem: NSStatusItem?
    private var taskTitle: String = ""

    func show(task: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.taskTitle = String(task.prefix(30))
            if self.statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
                item.button?.imagePosition = .imageLeading
                self.statusItem = item
            }
            self.setActive()
            self.updateButton("Starting...")
        }
    }

    func update(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.updateButton(status)
        }
    }

    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let item = self.statusItem else { return }
            NSStatusBar.system.removeStatusItem(item)
            self.statusItem = nil
        }
    }

    // MARK: - Icon States

    func setActive() {
        DispatchQueue.main.async { [weak self] in
            self?.setIcon("bolt.fill", tint: .systemGreen)
        }
    }

    func setPaused() {
        DispatchQueue.main.async { [weak self] in
            self?.setIcon("pause.circle.fill", tint: .systemYellow)
        }
    }

    func setError() {
        DispatchQueue.main.async { [weak self] in
            self?.setIcon("exclamationmark.triangle.fill", tint: .systemRed)
        }
    }

    // MARK: - Private

    private func setIcon(_ systemName: String, tint: NSColor) {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: "Presto")
        image?.isTemplate = false
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.image = image?.withSymbolConfiguration(config)
        button.contentTintColor = tint
    }

    private func updateButton(_ status: String) {
        guard let button = statusItem?.button else { return }
        let shortStatus = String(status.prefix(35))
        button.title = " \(shortStatus)"
        button.toolTip = "Presto: \(taskTitle)\n\(status)"
    }
}
