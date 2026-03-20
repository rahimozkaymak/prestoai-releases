import SwiftUI
import AppKit

// MARK: - Study Mode Notification (Corner Suggestion)

class StudyNotificationController {
    private var panel: NSPanel?
    private var autoDismissTimer: Timer?

    func show(suggestion: StudySuggestion, onAccept: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        dismiss()

        let view = StudyNotificationView(
            suggestionText: suggestion.suggestionText,
            onAccept: { [weak self] in
                self?.dismiss()
                onAccept()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
                onDismiss()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 110)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false

        // Position: top-right, 16px from edges
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 320 - 16
            let y = screenFrame.maxY - 110 - 16
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Slide-in animation
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        })

        self.panel = panel

        // Auto-dismiss after 10 seconds
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.dismiss()
            onDismiss()
        }
    }

    func dismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        self.panel = nil
    }
}

struct StudyNotificationView: View {
    let suggestionText: String
    let onAccept: () -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Presto")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text1(colorScheme))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.text3(colorScheme))
                }
                .buttonStyle(.plain)
            }

            // Suggestion text
            Text(suggestionText)
                .font(.system(size: 13))
                .foregroundColor(Theme.text2(colorScheme))
                .lineLimit(2)

            // Action buttons
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Text("Yes, help me")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.text1(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.subtleBg(colorScheme))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text3(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.bg(colorScheme))
                .shadow(color: Theme.shadowColor(colorScheme), radius: 16, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border(colorScheme), lineWidth: 0.5)
        )
    }
}

// StudyPromptBoxController and StudyPromptBoxView removed —
// Study Mode reuses the existing OverlayManager.showPromptInput() overlay
// (same UI as Cmd+Shift+Z) for a consistent experience.

// MARK: - Study Mode Onboarding Overlay

class StudyOnboardingController {
    private var panel: NSPanel?

    func show(onEnable: @escaping () -> Void, onCustomize: @escaping () -> Void) {
        let view = StudyOnboardingView(
            onEnable: { [weak self] in
                self?.dismiss()
                onEnable()
            },
            onCustomize: { [weak self] in
                self?.dismiss()
                onCustomize()
            }
        )

        let hostingView = NSHostingView(rootView: view)

        let panel = makePrestoPanel(size: NSSize(width: 420, height: 340))
        panel.contentView = hostingView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct StudyOnboardingView: View {
    let onEnable: () -> Void
    let onCustomize: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text("Study Mode")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Theme.text1(colorScheme))
                    .padding(.top, 32)

                Text("Presto will periodically analyze your screen to suggest help while you work.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text2(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 12) {
                    bulletPoint("Screenshots are analyzed and immediately discarded — never saved")
                    bulletPoint("Private apps (banking, messaging) are automatically excluded")
                    bulletPoint("You control capture frequency")
                    bulletPoint("Toggle off anytime with \u{2318}\u{21E7}S")
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: onCustomize) {
                    Text("Customize Exclusions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.text2(colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.subtleBg(colorScheme))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onEnable) {
                    Text("Enable Study Mode")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.text1(colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.subtleBg(colorScheme))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 420, height: 340)
        .background(Theme.bg(colorScheme))
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2726}")
                .font(.system(size: 10))
                .foregroundColor(Theme.text3(colorScheme))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Theme.text2(colorScheme))
        }
    }
}

// MARK: - Study Mode Settings View

struct StudyModeSettingsView: View {
    @AppStorage("studyModeCaptureInterval") private var captureInterval: Double = 45
    @AppStorage("studyModeSuggestionInterval") private var suggestionInterval: Double = 60
    @State private var excludedApps: [String] = UserDefaults.standard.stringArray(forKey: "studyModeExcludedApps") ?? []
    @State private var newAppName: String = ""
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Capture Frequency
            VStack(alignment: .leading, spacing: 6) {
                Text("Capture Frequency")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text4(colorScheme))
                HStack {
                    Slider(value: $captureInterval, in: 15...60, step: 15)
                        .tint(Theme.text3(colorScheme))
                    Text("\(Int(captureInterval))s")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text3(colorScheme))
                        .frame(width: 30, alignment: .trailing)
                }
            }
            .padding(.vertical, 12)

            rowDivider

            // Suggestion Frequency
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestion Frequency")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text4(colorScheme))
                HStack {
                    Slider(value: $suggestionInterval, in: 30...120, step: 30)
                        .tint(Theme.text3(colorScheme))
                    Text("\(Int(suggestionInterval))s")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text3(colorScheme))
                        .frame(width: 30, alignment: .trailing)
                }
            }
            .padding(.vertical, 12)

            rowDivider

            // Excluded Apps
            VStack(alignment: .leading, spacing: 8) {
                Text("Excluded Apps")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text4(colorScheme))

                Text("These apps are never captured during Study Mode")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text4(colorScheme))

                // Default exclusions (non-removable)
                ForEach(Array(PrivacyFilter.defaultExcludedApps).sorted(), id: \.self) { app in
                    HStack {
                        Text(app)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text3(colorScheme))
                        Spacer()
                        Text("default")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.text4(colorScheme))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }

                // User exclusions (removable)
                ForEach(excludedApps, id: \.self) { app in
                    HStack {
                        Text(app)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text2(colorScheme))
                        Spacer()
                        Button(action: { removeApp(app) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.text4(colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }

                // Add new app
                HStack {
                    TextField("App name...", text: $newAppName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text1(colorScheme))
                        .onSubmit { addApp() }

                    Button(action: addApp) {
                        Text("Add")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.text3(colorScheme))
                    }
                    .buttonStyle(.plain)
                    .disabled(newAppName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(8)
                .background(Theme.subtleBorder(colorScheme))
                .cornerRadius(6)
            }
            .padding(.vertical, 12)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.subtleBg(colorScheme))
            .frame(height: 1)
    }

    private func addApp() {
        let name = newAppName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !excludedApps.contains(name) else { return }
        excludedApps.append(name)
        UserDefaults.standard.set(excludedApps, forKey: "studyModeExcludedApps")
        newAppName = ""
    }

    private func removeApp(_ app: String) {
        excludedApps.removeAll { $0 == app }
        UserDefaults.standard.set(excludedApps, forKey: "studyModeExcludedApps")
    }
}

// MARK: - Session End Summary Notification

class StudySessionSummaryController {
    private var panel: NSPanel?

    func show(summary: String) {
        let view = StudySessionSummaryView(summary: summary)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 60)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 130
            let y = screenFrame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1.0
        })

        self.panel = panel

        // Auto-dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                self?.panel = nil
            })
        }
    }
}

struct StudySessionSummaryView: View {
    let summary: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Theme.text3(colorScheme))
            Text(summary)
                .font(.system(size: 13))
                .foregroundColor(Theme.text2(colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.bg(colorScheme))
                .shadow(color: Theme.shadowColor(colorScheme), radius: 12, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border(colorScheme), lineWidth: 0.5)
        )
    }
}
