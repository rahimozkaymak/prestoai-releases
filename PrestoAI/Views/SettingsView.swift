import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable {
    case settings = "Settings"
    case profile = "Profile"
    case myAccount = "My Account"
}

struct SettingsView: View {
    @ObservedObject private var stateManager = AppStateManager.shared
    @AppStorage("defaultPrompt") private var defaultPrompt = "Help me solve this problem. Be clear and concise. Use proper mathematical notation and LaTeX formatting for any math expressions."
    @State private var launchAtLogin = LaunchAtLoginManager.shared.isEnabled
    @State private var showSignOut = false
    @State private var selectedTab: SettingsTab
    @Environment(\.colorScheme) var colorScheme

    var onUpgrade: (() -> Void)?
    var onSignIn: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onFeedback: (() -> Void)?
    var onReferral: (() -> Void)?

    init(initialTab: SettingsTab = .settings, onUpgrade: (() -> Void)? = nil, onSignIn: (() -> Void)? = nil, onCheckForUpdates: (() -> Void)? = nil, onFeedback: (() -> Void)? = nil, onReferral: (() -> Void)? = nil) {
        _selectedTab = State(initialValue: initialTab)
        self.onUpgrade = onUpgrade
        self.onSignIn = onSignIn
        self.onCheckForUpdates = onCheckForUpdates
        self.onFeedback = onFeedback
        self.onReferral = onReferral
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker — fixed at top, never moves
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .tint(Theme.text3(colorScheme))
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Content
            Group {
                if selectedTab == .myAccount {
                    myAccountContent
                } else if selectedTab == .profile {
                    UserContextSettingsView()
                        .padding(.horizontal, 32)
                } else {
                    settingsContent
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            // Version — bottom center, consistent across both tabs
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.system(size: 13))
                .foregroundColor(Theme.text4(colorScheme).opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 16)
        }
        .frame(width: 420, height: 420)
        .background(Theme.bg(colorScheme))
        .alert("Sign Out", isPresented: $showSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task { @MainActor in AppStateManager.shared.signOut() }
            }
        } message: {
            Text("You'll need to sign in again to access your account.")
        }
    }

    // MARK: - My Account Tab

    private var myAccountContent: some View {
        VStack(spacing: 0) {
            // Profile header
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .colorMultiply(stateManager.currentState == .paid ? Color(red: 1.0, green: 0.78, blue: 0.08) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(stateManager.currentState == .paid ? "Pro Account" : "Free Tier")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.text1(colorScheme))

                Text(accountSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text3(colorScheme))
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 24)

            // Actions
            VStack(spacing: 10) {
                if stateManager.currentState != .paid {
                    // Primary CTA — filled blue button
                    Button(action: { onUpgrade?() }) {
                        Text("Upgrade to Pro")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Text("Unlimited analyses · \(stateManager.cachedPrice)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.text2(colorScheme))
                        .padding(.bottom, 4)
                }

                if stateManager.currentState == .paid {
                    settingsButton("Manage Subscription") {
                        if let url = URL(string: "https://polar.sh/purchases/subscriptions") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    settingsButton("Sign Out") { showSignOut = true }
                }
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 20)

            // Footer links
            VStack(spacing: 16) {
                Button(action: { onReferral?() }) {
                    Text("Refer a Friend — Get a Free Month")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text4(colorScheme))
                }
                .buttonStyle(.plain)

                if stateManager.accessToken == nil {
                    Button(action: { onSignIn?() ?? onUpgrade?() }) {
                        Text("Already have an account? Sign in")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text4(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Settings Tab

    private var settingsContent: some View {
        VStack(spacing: 16) {
            // Default Prompt
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Default Prompt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.text4(colorScheme))
                    Text("Sent with every analysis. Edit it to match how you like your answers.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text4(colorScheme))
                }

                TextEditor(text: $defaultPrompt)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text1(colorScheme))
                    .if_available_scrollContentBackgroundHidden()
                    .padding(10)
                    .background(Theme.subtleBorder(colorScheme))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.text4(colorScheme).opacity(0.15), lineWidth: 1)
                    )
                    .frame(height: 80)

                Button(action: resetDefaultPrompt) {
                    Text("Reset to Default")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Buttons
            VStack(spacing: 8) {
                // Launch at Login
                HStack {
                    Text("Launch at Login")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.text2(colorScheme))
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(Theme.text3(colorScheme))
                        .onChange(of: launchAtLogin) { enabled in
                            enabled ? LaunchAtLoginManager.shared.enable()
                                    : LaunchAtLoginManager.shared.disable()
                        }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Theme.subtleBg(colorScheme))
                .cornerRadius(10)

                settingsButton("Check for Updates…", action: { onCheckForUpdates?() })
                settingsButton("Send Feedback", action: { onFeedback?() })
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Reusable Button

    private func settingsButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.text2(colorScheme))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Theme.subtleBg(colorScheme))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var accountSubtitle: String {
        switch stateManager.currentState {
        case .paid:            return "Unlimited analyses · Active"
        case .referralActive:  return "Referral reward active"
        case .freeActive:      return "\(stateManager.queriesRemaining) free \(stateManager.queriesRemaining == 1 ? "analysis" : "analyses") remaining"
        case .freeExhausted:   return "You've used all \(stateManager.totalFreeQueries) free analyses"
        case .anonymous:       return "\(stateManager.totalFreeQueries) free analyses included"
        }
    }

    private func resetDefaultPrompt() {
        defaultPrompt = "Help me solve this problem. Be clear and concise. Use proper mathematical notation and LaTeX formatting for any math expressions."
    }
}

private extension View {
    @ViewBuilder
    func if_available_scrollContentBackgroundHidden() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
