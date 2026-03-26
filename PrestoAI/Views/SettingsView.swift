import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable {
    case settings = "Settings"
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
            // Tab picker — fixed position, always at the top
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .tint(Theme.text3(colorScheme))
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Content area — fixed height so tabs don't shift
            Group {
                if selectedTab == .myAccount {
                    myAccountContent
                } else {
                    settingsContent
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
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
        VStack(spacing: 16) {
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
            .padding(.top, 4)

            // Actions
            VStack(spacing: 8) {
                if stateManager.currentState != .paid {
                    settingsButton("Upgrade to Pro", action: { onUpgrade?() })

                    Text("Unlimited analyses · \(stateManager.cachedPrice)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.text2(colorScheme))
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

            // Footer links
            VStack(spacing: 8) {
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
        VStack(spacing: 12) {
            // Default Prompt
            VStack(alignment: .leading, spacing: 6) {
                Text("Default Prompt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text4(colorScheme))
                Text("Sent with every analysis. Edit it to match how you like your answers.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text4(colorScheme))

                TextEditor(text: $defaultPrompt)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text1(colorScheme))
                    .if_available_scrollContentBackgroundHidden()
                    .padding(10)
                    .background(Theme.subtleBorder(colorScheme))
                    .cornerRadius(8)
                    .frame(height: 80)

                Button(action: resetDefaultPrompt) {
                    Text("Reset to Default")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text4(colorScheme))
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
                .cornerRadius(8)

                settingsButton("Check for Updates…", action: { onCheckForUpdates?() })
                settingsButton("Send Feedback", action: { onFeedback?() })
            }

            Spacer()

            // Version
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.system(size: 11))
                .foregroundColor(Theme.text4(colorScheme))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 4)
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
                .cornerRadius(8)
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
