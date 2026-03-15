import SwiftUI
import AppKit

// MARK: - Upgrade Prompt (when free tier exhausted)

struct UpgradePromptView: View {
    @Environment(\.colorScheme) var colorScheme
    var onCreateAccount: () -> Void
    var onPromoCode: () -> Void
    var onDismiss: () -> Void
    
    // Presto.AI logo (same as menu bar icon 2x)
    private let prestoLogoB64 = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADDElEQVR4nO2YX2jNYRjHP+dsNmwYMskWJeVqKVwQtyhXytxgI5IkIbVLS0vLny32J4mZsWb+XOxSKBnzJ4lbJSklWW6UC6bj4v2+/R6vsz+/82+Up06/8z7v732ez/u8f57nHPgvhZWEPmP1/zVSpGeSHIMlZNSKb9cAKwIAG7WSwE7exDtvAbqJoBOmrxEYBm4CM6ULJxZL/IwWA8sNSAJYIJAfQEpOFwWgKeClnk+AisBubJhSoBhoAPpxsytVXwlQCfQCA8B8YKrGtgqiR+29at/X+KyiBHAH+BzovNE1wHqjPyPnXWr7PdQt/bJg/ITEL8kGoBn4JmNXgFpgCb+fHP88q/cuBTB1wAgwBEwj5qnzJ+QI8EEOUsBPPb8C7bjlSeKWFKBN/ZcDmG3SvwLmBROILVOA1cBHGd0KlBmjfgO3q/+W2n4vbZf+BTBXuoz3j717rgJvTV+RgTkvpyPAe2CV9PXSPwfmmHFZSbGM1AOnBFhiDHfKaSuwDncFDAPH8gFjpVyG7TL5yHSa92qALwZmdi4h0olfwgty2qF2qZ6bge/AoIGpxKWWdOknKxAfmYuCaQtgdkj/DHcjJ3GHohZ3IfrLNOt8ZmfWJafnAhh/mp4SpQcvHbio5SQ6FqabaANbmDrpHwOzpKsAVgKHgU/q7wU2AdWZwlmYHhltCWB2GhibzeuBd/x5qaaAPtz+Gq+wSwuTAK7J0OkAZpf0j4giY4/2dGAt8EbvNQALJwpgJWk+vTJ2MoDZLf0Q6escO/smXLqxfbFgfHT65LRZfT4d7CGKzFhFl7/NN+JKlwTu1GUE0y+nJwIYX9fYDTzeBi0DqvR9wtGxpaeHaQpg9kk/GAMmI/HrXYzL1ingeACzX/qHwIyYMLFPk79BB+S0MYA5IP0DXE6LAxNbfIF1YxSYg0S1cJkZkzcYgKVyej2AOVRIGIiWqxx4jaubt6jvqGDu4S64vMN48U6qcRWhzzkp4G6hYUKoKlzpkAJu434dFBwmhErifn16mdR/LkbLRZMqOS0z/1n5BUqXpG40It4WAAAAAElFTkSuQmCC"
    
    var body: some View {
        VStack(spacing: 20) {
            // Presto.AI Logo
            if let data = Data(base64Encoded: prestoLogoB64),
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(Theme.text1(colorScheme))
                    .frame(width: 48, height: 48)
            } else {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.text1(colorScheme))
            }
            
            Text("You've used all your free analyses")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))
            
            Text("Unlock unlimited for $5.99/month")
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(colorScheme))
            
            VStack(spacing: 12) {
                Button(action: onCreateAccount) {
                    Text("Create Account")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.text1(colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: onPromoCode) {
                    Text("I have a code")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text2(colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.inputBg(colorScheme))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: onDismiss) {
                    Text("Not now")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 280)
        }
        .padding(32)
        .frame(width: 420, height: 420)
        .background(Theme.bg(colorScheme))
    }
}

// MARK: - Account Creation/Sign In View

struct AccountView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var isSignIn = false
    @State private var email = ""
    @State private var password = ""
    @State private var promoCode = ""
    @State private var showPromoField = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var isLoading = false

    var onSuccess: (String) -> Void  // Called with JWT token
    var openPromoField: Bool = false
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.text1(colorScheme))
                
                Text(isSignIn ? "Sign In" : "Create Account")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.text1(colorScheme))
            }
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.text4(colorScheme))
                    
                    TextField("you@example.com", text: $email)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text1(colorScheme))
                        .padding(12)
                        .background(Theme.inputBg(colorScheme))
                        .cornerRadius(8)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.text4(colorScheme))

                    SecureField("••••••••", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text1(colorScheme))
                        .padding(12)
                        .background(Theme.inputBg(colorScheme))
                        .cornerRadius(8)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Button(action: handleSubmit) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    } else {
                        Text(isSignIn ? "Sign In" : "Continue")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.text1(colorScheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
                .buttonStyle(.plain)
                .background(isValidForm ? Color.blue : Color.blue.opacity(0.5))
                .cornerRadius(8)
                .disabled(!isValidForm || isLoading)
                
                Button(action: { isSignIn.toggle(); errorMessage = "" }) {
                    Text(isSignIn ? "Don't have an account? Create one" : "Already have an account? Sign in")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text4(colorScheme))
                }
                .buttonStyle(.plain)

                if showPromoField {
                    TextField("Enter code", text: $promoCode)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text1(colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Theme.subtleBorder(colorScheme))
                        .cornerRadius(5)
                        .autocorrectionDisabled()
                        .frame(width: 160, height: 20)
                } else {
                    Button(action: { showPromoField = true }) {
                        Text("I have a code")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.text3(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 300)
        }
        .padding(32)
        .frame(width: 420, height: 420)
        .background(Theme.bg(colorScheme))
        .onAppear { showPromoField = openPromoField }
    }

    private var isValidForm: Bool {
        // #23 — Better email validation
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let emailValid = email.range(of: emailRegex, options: .regularExpression) != nil
        return emailValid && password.count >= 8
    }
    
    private func handleSubmit() {
        errorMessage = ""
        successMessage = ""
        isLoading = true

        Task {
            do {
                let result: (profile: UserProfile, jwt: String)

                if isSignIn {
                    result = try await APIService.shared.login(email: email, password: password)
                } else {
                    result = try await APIService.shared.register(email: email, password: password)
                }

                // Redeem promo code if provided
                let trimmedPromo = promoCode.trimmingCharacters(in: .whitespaces)
                if showPromoField && !trimmedPromo.isEmpty {
                    do {
                        let promoResult = try await APIService.shared.redeemPromoCode(code: trimmedPromo, token: result.jwt)
                        await MainActor.run {
                            successMessage = promoResult
                        }
                    } catch {
                        await MainActor.run {
                            isLoading = false
                            errorMessage = "Account created but code redemption failed: \(error.localizedDescription)"
                        }
                        // Still call onSuccess — account was created
                        await MainActor.run {
                            onSuccess(result.jwt)
                            dismiss()
                        }
                        return
                    }
                }

                await MainActor.run {
                    isLoading = false
                    onSuccess(result.jwt)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    if errorMessage.contains("exist") || errorMessage.contains("already registered") {
                        isSignIn = true
                    }
                }
            }
        }
    }
}

// MARK: - Checkout Status View

struct CheckoutStatusView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var statusMessage = "Waiting for payment..."
    @State private var isPolling = true
    @State private var pollingTask: Task<Void, Never>?
    @State private var isTimedOut = false
    
    var checkoutURL: String
    var onSuccess: (String) -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
            
            Text(statusMessage)
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(colorScheme))
            
            Text("Complete your purchase in the browser window")
                .font(.system(size: 12))
                .foregroundColor(Theme.text3(colorScheme))
                .multilineTextAlignment(.center)
            
            Button(action: {
                pollingTask?.cancel()
                dismiss()
            }) {
                Text("Cancel")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text4(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .frame(width: 420, height: 420)
        .background(Theme.bg(colorScheme))
        .onAppear {
            openCheckoutInBrowser()
            startPolling()
        }
        .onDisappear {
            pollingTask?.cancel()
        }
    }
    
    private func openCheckoutInBrowser() {
        guard let url = URL(string: checkoutURL) else { return }
        NSWorkspace.shared.open(url)
    }
    
    private func startPolling() {
        pollingTask = Task {
            let startTime = Date()
            let maxDuration: TimeInterval = 300
            
            while !Task.isCancelled && Date().timeIntervalSince(startTime) < maxDuration {
                do {
                    // #12 — Don't call validateAuth with empty JWT
                    guard let jwt = AppStateManager.shared.jwt, !jwt.isEmpty else {
                        await MainActor.run {
                            statusMessage = "Not authenticated. Please sign in first."
                            pollingTask?.cancel()
                        }
                        return
                    }
                    let status = try await APIService.shared.validateAuth(token: jwt)

                    await MainActor.run {
                        // #27 — Ignore success if already timed out
                        guard !isTimedOut else { return }
                        if status.state == "paid" {
                            statusMessage = "You're all set. Press Cmd+Shift+X to continue."
                            pollingTask?.cancel()
                            // Use existing JWT from Keychain — Polar backend
                            // doesn't return a token in the status response
                            let jwt = AppStateManager.shared.jwt ?? ""
                            onSuccess(jwt)

                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                dismiss()
                            }
                            return
                        }
                    }
                } catch {
                    // Continue polling on error
                }
                
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            
            await MainActor.run {
                if !Task.isCancelled {
                    // #27 — Set timed out flag to prevent late success callbacks
                    isTimedOut = true
                    statusMessage = "Polling timed out. Please check your email."
                }
            }
        }
    }
}

// MARK: - Window Controllers (using shared makePrestoPanel)

class UpgradePromptController {
    private var window: NSWindow?
    
    func show(onCreateAccount: @escaping () -> Void, onPromoCode: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        let view = UpgradePromptView(onCreateAccount: onCreateAccount, onPromoCode: onPromoCode, onDismiss: {
            self.window?.close()
            self.window = nil
            onDismiss()
        })
        
        let panel = makePrestoPanel(size: NSSize(width: 420, height: 420), title: "Upgrade to Pro")
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }
}

class AccountViewController {
    private var window: NSWindow?
    
    func show(openPromoField: Bool = false, onSuccess: @escaping (String) -> Void) {
        let view = AccountView(onSuccess: { jwt in
            self.window?.close()
            self.window = nil
            onSuccess(jwt)
        }, openPromoField: openPromoField)
        
        let panel = makePrestoPanel(size: NSSize(width: 420, height: 420), title: "Account")
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }
}

class CheckoutViewController {
    private var window: NSWindow?
    
    func show(checkoutURL: String, onSuccess: @escaping (String) -> Void) {
        let view = CheckoutStatusView(checkoutURL: checkoutURL, onSuccess: { jwt in
            self.window?.close()
            self.window = nil
            onSuccess(jwt)
        })
        
        let panel = makePrestoPanel(size: NSSize(width: 420, height: 420), title: "Checkout")
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }
}
