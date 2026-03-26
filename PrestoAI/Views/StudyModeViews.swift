import SwiftUI
import AppKit

// Suggestion notification and session summary are rendered via OverlayManager
// (showStudySuggestion / showStudySummary) using the same WKWebView + frosted
// glass panel as the main answer overlay.

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

