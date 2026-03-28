import SwiftUI
import AppKit
import AuthenticationServices

// MARK: - Design Constants

private let kCornerRadius: CGFloat = 10
private let kPrimaryButtonHeight: CGFloat = 48
private let kSecondaryButtonHeight: CGFloat = 40
private let kContentWidth: CGFloat = 280
private let kPanelSize = NSSize(width: 420, height: 420)

// MARK: - Upgrade Prompt (when free tier exhausted)

struct UpgradePromptView: View {
    @Environment(\.colorScheme) var colorScheme
    var onCreateAccount: () -> Void
    var onPromoCode: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer().frame(height: 16)

            Text("You've used all your free analyses")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))

            Spacer().frame(height: 8)

            Text("Unlock unlimited for \(AppStateManager.shared.cachedPrice)")
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(colorScheme))

            Spacer().frame(height: 24)

            VStack(spacing: 10) {
                Button(action: onCreateAccount) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: kContentWidth, height: kPrimaryButtonHeight)
                        .background(Color.blue)
                        .cornerRadius(kCornerRadius)
                }
                .buttonStyle(.plain)

                Button(action: onPromoCode) {
                    Text("I have a code")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text2(colorScheme))
                        .frame(width: kContentWidth, height: kSecondaryButtonHeight)
                        .background(Theme.inputBg(colorScheme))
                        .cornerRadius(kCornerRadius)
                }
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 16)

            Button(action: onDismiss) {
                Text("Not now")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text4(colorScheme))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(width: kPanelSize.width, height: kPanelSize.height)
        .background(Theme.bg(colorScheme))
    }
}

// MARK: - Account Creation/Sign In View

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

    var onSuccess: (String) -> Void
    var openPromoField: Bool = false
    var showBackButton: Bool = false
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Back button (when opened from Settings)
            if showBackButton {
                HStack {
                    Button(action: { onBack?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .medium))
                            Text("Back")
                                .font(.system(size: 15))
                        }
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.horizontal, 8)
            }

            Spacer()

            // Header
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

            Spacer().frame(height: 24)

            if showEmailForm {
                emailFormSection
            } else {
                socialAuthSection
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(width: kPanelSize.width, height: kPanelSize.height)
        .background(Theme.bg(colorScheme))
        .onAppear { showPromoField = openPromoField }
    }

    // MARK: - Social Auth (Primary)

    private var socialAuthSection: some View {
        VStack(spacing: 16) {
            // Apple — native button (required by Apple HIG)
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(width: kContentWidth, height: kPrimaryButtonHeight)
            .cornerRadius(kCornerRadius)

            // Google — branded per Google Identity guidelines
            Button(action: handleGoogleSignIn) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                        Text("G")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                    }
                    Text("Continue with Google")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: 0xE3E3E3))
                }
                .frame(width: kContentWidth, height: kPrimaryButtonHeight)
                .background(Color(hex: 0x131314))
                .cornerRadius(kCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: kCornerRadius)
                        .stroke(Color(hex: 0x8E918F), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .frame(width: kContentWidth, alignment: .leading)
            }

            // Divider
            HStack(spacing: 12) {
                Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
                Text("or")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.text3(colorScheme))
                Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
            }
            .frame(width: kContentWidth)

            // Email fallback
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showEmailForm = true } }) {
                Text("Continue with email")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.text1(colorScheme))
                    .frame(width: kContentWidth, height: kPrimaryButtonHeight)
                    .background(Theme.inputBg(colorScheme))
                    .cornerRadius(kCornerRadius)
            }
            .buttonStyle(.plain)
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
                    .cornerRadius(kCornerRadius)
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
                    .cornerRadius(kCornerRadius)
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
                        .frame(height: kPrimaryButtonHeight)
                } else {
                    Text(isSignIn ? "Sign In" : "Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: kPrimaryButtonHeight)
                }
            }
            .buttonStyle(.plain)
            .background(isValidForm ? Color.blue : Color.blue.opacity(0.5))
            .cornerRadius(kCornerRadius)
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
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text4(colorScheme))
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
                    .cornerRadius(6)
                    .autocorrectionDisabled()
                    .frame(width: 160, height: 24)
            } else {
                Button(action: { showPromoField = true }) {
                    Text("I have a code")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text4(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: kContentWidth + 20)
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
            let appleEmail = credential.email

            isLoading = true
            errorMessage = ""

            Task {
                do {
                    let jwt = try await APIService.shared.appleSignIn(
                        identityToken: identityToken,
                        fullName: fullName.isEmpty ? nil : fullName,
                        email: appleEmail
                    )
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

struct CheckoutStatusView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var statusMessage = "Opening checkout..."
    @State private var pollingTask: Task<Void, Never>?
    var checkoutURL: String
    var onSuccess: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)

            Spacer().frame(height: 20)

            Text(statusMessage)
                .font(.system(size: 15))
                .foregroundColor(Theme.text2(colorScheme))

            Spacer().frame(height: 8)

            Text("Complete your purchase in the checkout window.\nApple Pay is available if configured on this Mac.")
                .font(.system(size: 13))
                .foregroundColor(Theme.text3(colorScheme))
                .multilineTextAlignment(.center)

            Spacer().frame(height: 24)

            Button(action: {
                pollingTask?.cancel()
                dismiss()
            }) {
                Text("Cancel")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text4(colorScheme))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(width: kPanelSize.width, height: kPanelSize.height)
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

// MARK: - Window Controllers

class UpgradePromptController {
    private var window: NSWindow?

    func show(onCreateAccount: @escaping () -> Void, onPromoCode: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        let view = UpgradePromptView(onCreateAccount: onCreateAccount, onPromoCode: onPromoCode, onDismiss: {
            self.window?.close()
            self.window = nil
            onDismiss()
        })

        let panel = makePrestoPanel(size: kPanelSize, title: "")
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }
}

class AccountViewController {
    private var window: NSWindow?
    var onBack: (() -> Void)?

    func show(openPromoField: Bool = false, showBackButton: Bool = false, onSuccess: @escaping (String) -> Void) {
        let view = AccountView(onSuccess: { jwt in
            self.window?.close()
            self.window = nil
            onSuccess(jwt)
        }, openPromoField: openPromoField, showBackButton: showBackButton, onBack: { [weak self] in
            self?.window?.close()
            self?.window = nil
            self?.onBack?()
        })

        let panel = makePrestoPanel(size: kPanelSize, title: "")
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

        let panel = makePrestoPanel(size: kPanelSize, title: "")
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }
}

// MARK: - Soft Sign-In Nudge

struct SignInNudgeView: View {
    @Environment(\.colorScheme) var colorScheme
    var onSignIn: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "person.badge.plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Theme.text1(colorScheme))

            Spacer().frame(height: 16)

            Text("Sign in to save your progress")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))

            Spacer().frame(height: 8)

            Text("Keep your history and get a seamless experience when you upgrade later.")
                .font(.system(size: 13))
                .foregroundColor(Theme.text2(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            Spacer().frame(height: 20)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { _ in
                onSignIn()
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(width: 240, height: 44)
            .cornerRadius(kCornerRadius)

            Spacer().frame(height: 12)

            Button(action: onDismiss) {
                Text("Not now")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text4(colorScheme))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(24)
        .frame(width: 320, height: 300)
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

        let panel = makePrestoPanel(size: NSSize(width: 320, height: 300), title: "")
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
        VStack(spacing: 0) {
            Spacer()

            switch step {
            case .enterEmail: emailStep
            case .enterCode: codeStep
            case .success: successStep
            }

            Spacer()
        }
        .frame(width: kPanelSize.width, height: kPanelSize.height)
        .background(Theme.bg(colorScheme))
    }

    private var emailStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 24, weight: .medium))
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
                    .cornerRadius(kCornerRadius)
                    .autocorrectionDisabled()

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }

                Button(action: requestReset) {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular).controlSize(.small)
                            .frame(maxWidth: .infinity).frame(height: kPrimaryButtonHeight)
                    } else {
                        Text("Send Reset Code")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: kPrimaryButtonHeight)
                    }
                }
                .buttonStyle(.plain)
                .background(Color.blue)
                .cornerRadius(kCornerRadius)
                .disabled(email.isEmpty || isLoading)

                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .frame(width: kContentWidth)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 24, weight: .medium))
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
                    .cornerRadius(kCornerRadius)
                    .frame(width: 180)

                SecureField("New password", text: $newPassword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text1(colorScheme))
                    .padding(12)
                    .background(Theme.inputBg(colorScheme))
                    .cornerRadius(kCornerRadius)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }

                Button(action: submitReset) {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular).controlSize(.small)
                            .frame(maxWidth: .infinity).frame(height: kPrimaryButtonHeight)
                    } else {
                        Text("Reset Password")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: kPrimaryButtonHeight)
                    }
                }
                .buttonStyle(.plain)
                .background(Color.blue)
                .cornerRadius(kCornerRadius)
                .disabled(code.count < 6 || newPassword.count < 8 || isLoading)

                Button(action: { step = .enterEmail; errorMessage = "" }) {
                    Text("Back")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .frame(width: kContentWidth)
        }
    }

    private var successStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.green)

            Text("Password Reset!")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))

            Text("You can now sign in with your new password.")
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(colorScheme))

            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: kPrimaryButtonHeight)
            }
            .buttonStyle(.plain)
            .background(Color.blue)
            .cornerRadius(kCornerRadius)
            .frame(width: kContentWidth)
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

// MARK: - Color Hex Extension

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
