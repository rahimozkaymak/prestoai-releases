import SwiftUI
import AppKit
import AuthenticationServices

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
            
            Text("Unlock unlimited for \(AppStateManager.shared.cachedPrice)")
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(colorScheme))
            
            VStack(spacing: 12) {
                Button(action: onCreateAccount) {
                    Text("Continue")
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
// Social auth (Apple/Google) is the primary flow; email is a fallback.

struct AccountView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var showEmailForm = false
    @State private var isSignIn = false
    @State private var email = ""
    @State private var password = ""
    @State private var promoCode = ""
    @State private var showPromoField = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var isLoading = false
    @State private var showPasswordReset = false

    var onSuccess: (String) -> Void  // Called with JWT token
    var openPromoField: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(showEmailForm ? (isSignIn ? "Sign In" : "Create Account") : "Continue with")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.text1(colorScheme))
            }

            if showEmailForm {
                emailFormSection
            } else {
                socialAuthSection
            }
        }
        .padding(32)
        .frame(width: 420, height: 460)
        .background(Theme.bg(colorScheme))
        .onAppear { showPromoField = openPromoField }
    }

    // MARK: - Social Auth (Primary)

    private var socialAuthSection: some View {
        VStack(spacing: 12) {
            // Sign in with Apple — native button
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(width: 280, height: 44)
            .cornerRadius(8)

            // Sign in with Google — custom styled button
            Button(action: handleGoogleSignIn) {
                HStack(spacing: 10) {
                    Text("G")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(
                            LinearGradient(
                                colors: [.red, .yellow, .green, .blue],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(4)
                    Text("Sign in with Google")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.text1(colorScheme))
                }
                .frame(width: 280, height: 44)
                .background(Theme.inputBg(colorScheme))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border(colorScheme), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .padding(.top, 4)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .frame(width: 300, alignment: .leading)
            }

            // Divider
            HStack {
                Rectangle().fill(Theme.border(colorScheme)).frame(height: 1)
                Text("or")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text4(colorScheme))
                Rectangle().fill(Theme.border(colorScheme)).frame(height: 1)
            }
            .frame(width: 280)
            .padding(.vertical, 2)

            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showEmailForm = true } }) {
                Text("Continue with email")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.text1(colorScheme))
                    .frame(width: 280, height: 44)
                    .background(Theme.inputBg(colorScheme))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            if showPromoField {
                TextField("Enter code", text: $promoCode)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text1(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Theme.subtleBorder(colorScheme))
                    .cornerRadius(5)
                    .autocorrectionDisabled()
                    .frame(width: 140, height: 20)
            } else {
                Button(action: { showPromoField = true }) {
                    Text("I have a code")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text4(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Email Form (Fallback)

    private var emailFormSection: some View {
        VStack(spacing: 14) {
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

            Button(action: handleEmailSubmit) {
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

            HStack(spacing: 16) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showEmailForm = false; errorMessage = "" } }) {
                    Text("Back")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3(colorScheme))
                }
                .buttonStyle(.plain)

                Button(action: { isSignIn.toggle(); errorMessage = "" }) {
                    Text(isSignIn ? "Create account" : "Sign in instead")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text4(colorScheme))
                }
                .buttonStyle(.plain)
            }

            if isSignIn {
                Button(action: { showPasswordReset = true }) {
                    Text("Forgot password?")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3(colorScheme))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showPasswordReset) {
                    PasswordResetView()
                }
            }

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

    // MARK: - Validation

    private var isValidForm: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let emailValid = email.range(of: emailRegex, options: .regularExpression) != nil
        return emailValid && password.count >= 8
    }

    // MARK: - Apple Sign-In

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Could not retrieve Apple ID credentials."
                return
            }

            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let appleEmail = credential.email  // Only provided on first auth

            isLoading = true
            errorMessage = ""

            Task {
                do {
                    let jwt = try await APIService.shared.appleSignIn(
                        identityToken: identityToken,
                        fullName: fullName.isEmpty ? nil : fullName,
                        email: appleEmail
                    )
                    // Redeem promo code if entered
                    await redeemPromoIfNeeded(jwt: jwt)
                    await MainActor.run {
                        isLoading = false
                        onSuccess(jwt)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = error.localizedDescription
                    }
                }
            }

        case .failure(let error):
            // User cancelled — don't show an error for cancellation
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Google Sign-In

    private func handleGoogleSignIn() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let jwt = try await GoogleSignInHelper.signIn()
                await redeemPromoIfNeeded(jwt: jwt)
                await MainActor.run {
                    isLoading = false
                    onSuccess(jwt)
                    dismiss()
                }
            } catch let error as GoogleSignInHelper.GoogleAuthError {
                await MainActor.run {
                    isLoading = false
                    if case .cancelled = error { return }
                    errorMessage = error.localizedDescription
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Email Submit

    private func handleEmailSubmit() {
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

                await redeemPromoIfNeeded(jwt: result.jwt)
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

    // MARK: - Promo Code Helper

    private func redeemPromoIfNeeded(jwt: String) async {
        let trimmedPromo = promoCode.trimmingCharacters(in: .whitespaces)
        guard showPromoField, !trimmedPromo.isEmpty else { return }
        do {
            let result = try await APIService.shared.redeemPromoCode(code: trimmedPromo, token: jwt)
            await MainActor.run { successMessage = result }
        } catch {
            await MainActor.run {
                errorMessage = "Account created but code failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Checkout Status View
// Opens Polar checkout in-app via ASWebAuthenticationSession so Apple Pay works.
// Falls back to browser + polling if the session can't be presented.

struct CheckoutStatusView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var statusMessage = "Opening checkout..."
    @State private var pollingTask: Task<Void, Never>?
    @State private var sessionStarted = false
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

            Text("Complete your purchase in the checkout window.\nApple Pay is available if configured on this Mac.")
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
            openCheckout()
            startPolling()
        }
        .onDisappear {
            pollingTask?.cancel()
        }
    }

    private func openCheckout() {
        guard let url = URL(string: checkoutURL) else { return }
        // Open in default browser — Polar's checkout supports Apple Pay in Safari.
        // ASWebAuthenticationSession doesn't support Apple Pay on macOS,
        // but Safari does when the user has Apple Pay configured.
        NSWorkspace.shared.open(url)
        statusMessage = "Waiting for payment..."
    }

    private func startPolling() {
        pollingTask = Task {
            let startTime = Date()

            while !Task.isCancelled {
                do {
                    guard let jwt = AppStateManager.shared.jwt, !jwt.isEmpty else {
                        await MainActor.run {
                            statusMessage = "Not authenticated. Please sign in first."
                            pollingTask?.cancel()
                        }
                        return
                    }
                    let status = try await APIService.shared.validateAuth(token: jwt)
                    print("[Checkout] Poll result: state=\(status.state), email=\(status.email ?? "nil")")

                    await MainActor.run {
                        if status.state == "paid" {
                            statusMessage = "You're all set! Press Cmd+Shift+X to continue."
                            pollingTask?.cancel()
                            let jwt = AppStateManager.shared.jwt ?? ""
                            onSuccess(jwt)

                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                dismiss()
                            }
                            return
                        }
                    }
                } catch {
                    print("[Checkout] Poll error: \(error)")
                }

                let elapsed = Date().timeIntervalSince(startTime)
                let interval: UInt64 = elapsed < 120 ? 500_000_000 : 3_000_000_000
                try? await Task.sleep(nanoseconds: interval)
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
        
        let panel = makePrestoPanel(size: NSSize(width: 420, height: 460), title: "Account")
        panel.hidesOnDeactivate = false
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

// MARK: - Soft Sign-In Nudge (dismissible, shown once after 3rd free use)

struct SignInNudgeView: View {
    @Environment(\.colorScheme) var colorScheme
    var onSignIn: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(Theme.text1(colorScheme))

            Text("Sign in to save your progress")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))

            Text("Keep your history and get a seamless\nexperience when you upgrade later.")
                .font(.system(size: 13))
                .foregroundColor(Theme.text2(colorScheme))
                .multilineTextAlignment(.center)

            // Apple Sign-In button
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { _ in
                // Delegate handling to the parent controller
                onSignIn()
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(width: 240, height: 44)
            .cornerRadius(8)

            Button(action: onDismiss) {
                Text("Not now")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text3(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(width: 320, height: 280)
        .background(Theme.bg(colorScheme))
    }
}

class SignInNudgeController {
    private var window: NSWindow?

    func show(onSignIn: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        let view = SignInNudgeView(
            onSignIn: { [weak self] in
                self?.window?.close()
                self?.window = nil
                onSignIn()
            },
            onDismiss: { [weak self] in
                self?.window?.close()
                self?.window = nil
                onDismiss()
            }
        )

        let panel = makePrestoPanel(size: NSSize(width: 320, height: 280), title: "")
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }
}

// MARK: - Password Reset View

struct PasswordResetView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var step: ResetStep = .enterEmail
    @State private var errorMessage = ""
    @State private var isLoading = false

    enum ResetStep {
        case enterEmail
        case enterCode
        case success
    }

    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .enterEmail:
                emailStep
            case .enterCode:
                codeStep
            case .success:
                successStep
            }
        }
        .padding(32)
        .frame(width: 420, height: 420)
        .background(Theme.bg(colorScheme))
    }

    private var emailStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.text2(colorScheme))

            Text("Reset Password")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))

            Text("Enter your email and we'll send you a reset code")
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(colorScheme))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text1(colorScheme))
                    .padding(12)
                    .background(Theme.inputBg(colorScheme))
                    .cornerRadius(8)
                    .autocorrectionDisabled()

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }

                Button(action: requestReset) {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular).controlSize(.small)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    } else {
                        Text("Send Reset Code")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.text1(colorScheme))
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                }
                .buttonStyle(.plain)
                .background(Color.blue)
                .cornerRadius(8)
                .disabled(email.isEmpty || isLoading)

                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 300)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.text2(colorScheme))

            Text("Check Your Email")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))

            Text("Enter the 6-digit code sent to \(email)")
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(colorScheme))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("000000", text: $code)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.text1(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(Theme.inputBg(colorScheme))
                    .cornerRadius(8)
                    .frame(width: 180)

                SecureField("New password", text: $newPassword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text1(colorScheme))
                    .padding(12)
                    .background(Theme.inputBg(colorScheme))
                    .cornerRadius(8)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }

                Button(action: submitReset) {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular).controlSize(.small)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    } else {
                        Text("Reset Password")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.text1(colorScheme))
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                }
                .buttonStyle(.plain)
                .background(Color.blue)
                .cornerRadius(8)
                .disabled(code.count < 6 || newPassword.count < 8 || isLoading)

                Button(action: { step = .enterEmail; errorMessage = "" }) {
                    Text("Back")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 300)
        }
    }

    private var successStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Password Reset!")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))

            Text("You can now sign in with your new password.")
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(colorScheme))

            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text1(colorScheme))
                    .frame(maxWidth: .infinity).frame(height: 44)
            }
            .buttonStyle(.plain)
            .background(Color.blue)
            .cornerRadius(8)
            .frame(width: 300)
        }
    }

    private func requestReset() {
        isLoading = true
        errorMessage = ""
        Task {
            do {
                try await APIService.shared.requestPasswordReset(email: email)
                await MainActor.run {
                    isLoading = false
                    step = .enterCode
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func submitReset() {
        isLoading = true
        errorMessage = ""
        Task {
            do {
                try await APIService.shared.resetPassword(email: email, code: code, newPassword: newPassword)
                await MainActor.run {
                    isLoading = false
                    step = .success
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
