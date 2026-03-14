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

    var onUpgrade: (() -> Void)?

    init(initialTab: SettingsTab = .settings, onUpgrade: (() -> Void)? = nil) {
        _selectedTab = State(initialValue: initialTab)
        self.onUpgrade = onUpgrade
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {

                // MARK: Segmented Toggle
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color(white: 0.55))
                .padding(.top, 20)
                .padding(.bottom, 8)

                if selectedTab == .myAccount {
                    myAccountContent
                } else {
                    settingsContent
                }
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 0)
        }
        .frame(width: 420, height: 420)
        .background(Color(red: 0.039, green: 0.039, blue: 0.039))
        .preferredColorScheme(.dark)
        .alert("Sign Out", isPresented: $showSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task { @MainActor in AppStateManager.shared.signOut() }
            }
        } message: {
            Text("You've been signed out. Your free queries have been used.")
        }
    }

    // MARK: - My Account Tab

    private var myAccountContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                if stateManager.currentState == .paid {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .colorMultiply(Color(red: 1.0, green: 0.78, blue: 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }

                Text(stateManager.currentState == .paid ? "Pro Account" : "Free Tier")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)

                Text(accountSubtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            // Upgrade CTA (free users)
            if stateManager.currentState != .paid {
                VStack(spacing: 8) {
                    Button(action: { onUpgrade?() }) {
                        Text("Upgrade to Pro")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Text("Unlimited analyses · $5.99/month")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.bottom, 20)
            }

            // Manage Subscription + Sign Out (paid users)
            if stateManager.currentState == .paid {
                rowDivider

                Button(action: {
                    if let url = URL(string: "https://polar.sh/purchases/subscriptions") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Manage Subscription")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)

                Button(action: { showSignOut = true }) {
                    Text("Sign Out")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Settings Tab

    private var settingsContent: some View {
        VStack(spacing: 0) {
            rowDivider

            // Default Prompt
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Default Prompt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Sent with every screenshot analysis")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }

                TextEditor(text: $defaultPrompt)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                    .frame(height: 90)

                Button(action: resetDefaultPrompt) {
                    Text("Reset to Default")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)

            rowDivider

            // Launch at Login
            HStack {
                Text("Launch at Login")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Color(white: 0.5))
                    .onChange(of: launchAtLogin) { enabled in
                        enabled ? LaunchAtLoginManager.shared.enable()
                                : LaunchAtLoginManager.shared.disable()
                    }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.white.opacity(0.07))
            .cornerRadius(8)
            .padding(.top, 16)

            Button(action: {
                NotificationCenter.default.post(name: .rerunSetupWizard, object: nil)
            }) {
                Text("Run Setup Again")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            // Version
            Text("v1.0.0")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 20)
                .padding(.bottom, 16)
        }
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

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }

    private func resetDefaultPrompt() {
        defaultPrompt = "Help me solve this problem. Be clear and concise. Use proper mathematical notation and LaTeX formatting for any math expressions."
    }
}

#Preview {
    SettingsView()
}
