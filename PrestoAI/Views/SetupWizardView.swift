import SwiftUI


// MARK: - Brand logo (embedded, template image — renders white)
private let prestoIconB64 = "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"

private func prestoLogoImage(size: CGFloat) -> Image {
    guard let data = Data(base64Encoded: prestoIconB64),
          let nsImg = NSImage(data: data) else { return Image(systemName: "wand.and.rays") }
    nsImg.isTemplate = true
    return Image(nsImage: nsImg)
}

// MARK: - Color palette
private enum WZ {
    static let bg        = Color(red: 0.039, green: 0.039, blue: 0.039)  // #0A0A0A
    static let surface   = Color(red: 0.110, green: 0.110, blue: 0.110)  // #1C1C1C
    static let border    = Color(red: 0.165, green: 0.165, blue: 0.165)  // #2A2A2A
    static let keyBg     = Color(red: 0.133, green: 0.133, blue: 0.133)  // #222
    static let keyBorder = Color(red: 0.200, green: 0.200, blue: 0.200)  // #333
    static let keyActive = Color(red: 0.180, green: 0.180, blue: 0.180)  // #2E2E2E
    static let keyFlash  = Color(red: 0.220, green: 0.220, blue: 0.220)  // #383838
    static let text1     = Color(red: 0.878, green: 0.878, blue: 0.878)  // #E0E0E0
    static let text2     = Color(red: 0.467, green: 0.467, blue: 0.467)  // #777
    static let text3     = Color(red: 0.333, green: 0.333, blue: 0.333)  // #555
    static let text4     = Color(red: 0.400, green: 0.400, blue: 0.400)  // #666
    static let textDot   = Color(red: 0.533, green: 0.533, blue: 0.533)  // #888
}

// MARK: - Persisted Onboarding State
enum OnboardingState: Int {
    case notStarted = 0        // Fresh install, show welcome
    case permissionRequested = 1  // User clicked "Let's go", waiting for permission
    case completed = 2          // Wizard finished
}

// MARK: - Wizard Start Mode
enum WizardStartMode {
    case fresh              // First launch — show welcome page
    case resumeGranted      // Relaunched after Quit & Reopen, permission already propagated
    case resumePending      // Relaunched after Quit & Reopen, permission not yet detected
}

// Notification posted by "Run Setup Again" button (avoids fragile AppDelegate cast)
extension Notification.Name {
    static let rerunSetupWizard = Notification.Name("rerunSetupWizard")
}

// MARK: - Setup Wizard

struct SetupWizardView: View {
    var onComplete: () -> Void
    var startMode: WizardStartMode = .fresh

    @State private var currentStep = 0
    @State private var screenRecordingGranted = false
    @State private var permissionJustGranted = false
    @State private var timer: Timer?
    @State private var stepEnteredTime: Date?
    
    // Welcome animations
    @State private var showWelcome = false
    @State private var showTo = false
    @State private var showBrand = false
    @State private var brandGlow = false
    @State private var showSubtitle = false
    
    // Permission granted animation
    @State private var showGrantedCheck = false
    @State private var showGrantedText = false
    
    // Done animations
    @State private var showReadyText = false
    @State private var showOutroKeys = false
    @State private var keyCmdLit = false
    @State private var keyShiftLit = false
    @State private var keyXLit = false
    @State private var keysFlash = false
    @State private var showMenuHint = false

    // Referral code entry
    @State private var showReferralField = false
    @State private var referralCodeInput = ""
    @State private var referralMessage = ""
    @State private var referralIsError = false
    @State private var isSubmittingReferral = false
    
    private let totalSteps = 3
    
    var body: some View {
        VStack(spacing: 0) {
            // Room for traffic light buttons
            Color.clear.frame(height: 28)
            
            // Content (centered)
            Group {
                switch currentStep {
                case 0: welcomeContent
                case 1: screenRecordingContent
                case 2: doneContent
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom button area (pinned)
            bottomActions
            
            // Dots
            bottomDots
        }
        .frame(width: 600, height: 520)
        .background(WZ.bg)
        .onAppear {
            startPolling()
            stepEnteredTime = Date()

            switch startMode {
            case .fresh:
                // First launch or "Run Setup Again" — always show welcome page.
                currentStep = 0
                runWelcomeAnimation()

            case .resumeGranted:
                // Relaunched after Quit & Reopen, permission already propagated.
                currentStep = 1
                triggerGrantedAnimation()

            case .resumePending:
                // Relaunched after Quit & Reopen, permission not yet detected.
                // Go to step 1 and let the polling timer detect permission.
                currentStep = 1
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // =========================================================================
    // MARK: - Step 0: Welcome (content only, no button)
    // =========================================================================
    
    private var welcomeContent: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // "Welcome to"
            HStack(spacing: 12) {
                Text("Welcome")
                    .font(.system(size: 49, weight: .light))
                    .tracking(-0.5)
                    .foregroundColor(WZ.text1)
                    .opacity(showWelcome ? 1 : 0)
                    .offset(y: showWelcome ? 0 : 14)
                
                Text("to")
                    .font(.system(size: 49, weight: .light))
                    .tracking(-0.5)
                    .foregroundColor(WZ.text1)
                    .opacity(showTo ? 1 : 0)
                    .offset(y: showTo ? 0 : 14)
            }
            
            // Logo + "presto.ai" inline — logo scaled to match text cap-height
            HStack(alignment: .center, spacing: 14) {
                prestoLogoImage(size: 44)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)

                HStack(spacing: 0) {
                    Text("presto")
                        .font(.system(size: 55, weight: .semibold))
                        .tracking(-2)
                        .foregroundColor(.white)
                    Text(".")
                        .font(.system(size: 55, weight: .semibold))
                        .tracking(-2)
                        .foregroundColor(WZ.textDot)
                    Text("ai")
                        .font(.system(size: 55, weight: .semibold))
                        .tracking(-2)
                        .foregroundColor(.white)
                }
            }
            .opacity(showBrand ? 1 : 0)
            .offset(y: showBrand ? 0 : 14)
            .shadow(color: brandGlow ? .white.opacity(0.8) : .clear, radius: brandGlow ? 30 : 0)
            .padding(.top, 10)
            
            Spacer()
        }
    }
    
    private func runWelcomeAnimation() {
        guard currentStep == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.7)) { showWelcome = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.7)) { showTo = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.8)) { showBrand = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.08)) { brandGlow = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            withAnimation(.easeOut(duration: 0.6)) { brandGlow = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.7)) { showSubtitle = true }
        }
    }
    
    // =========================================================================
    // MARK: - Step 1: Screen Recording (content only)
    // =========================================================================
    
    private var screenRecordingContent: some View {
        VStack(spacing: 0) {
            Spacer()
            
            if permissionJustGranted {
                grantedView
            } else {
                pendingView
            }
            
            Spacer()
        }
    }
    
    private var grantedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 57, weight: .light))
                .foregroundColor(.white)
                .opacity(showGrantedCheck ? 1 : 0)
                .scaleEffect(showGrantedCheck ? 1 : 0.5)
            
            Text("Permission granted")
                .font(.system(size: 25, weight: .light))
                .foregroundColor(.white)
                .tracking(0.3)
                .opacity(showGrantedText ? 1 : 0)
                .offset(y: showGrantedText ? 0 : 6)
        }
    }
    
    private var pendingView: some View {
        VStack(spacing: 0) {
            // Icon + title (centered)
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 45, weight: .light))
                .foregroundColor(WZ.text2)
            
            Text("Screen Recording")
                .font(.system(size: 29, weight: .medium))
                .tracking(-0.5)
                .foregroundColor(WZ.text1)
                .padding(.top, 14)
            
            // Explanation
            Text("Presto.AI needs this to capture the region you select")
                .font(.system(size: 19, weight: .light))
                .foregroundColor(WZ.text2)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            
            Spacer().frame(height: 40)
            
            // Hints (in the middle)
            VStack(spacing: 8) {
                Text("Find **Presto.AI** in the list and toggle it on")
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(WZ.text4)
                
                Text("If prompted, click \"Quit & Reopen\"")
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(WZ.text4)
            }
        }
    }
    
    private func triggerGrantedAnimation() {
        screenRecordingGranted = true
        withAnimation(.easeInOut(duration: 0.3)) {
            permissionJustGranted = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showGrantedCheck = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                showGrantedText = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                currentStep = 2
            }
        }
    }
    
    // =========================================================================
    // MARK: - Step 2: Done (content only)
    // =========================================================================
    
    private var doneContent: some View {
        VStack(spacing: 0) {
            Spacer()
            
            Text("Ready when you are.")
                .font(.system(size: 47, weight: .light))
                .tracking(-1)
                .foregroundColor(WZ.text1)
                .opacity(showReadyText ? 1 : 0)
                .offset(y: showReadyText ? 0 : 10)
            
            HStack(spacing: 8) {
                keyView(symbol: "\u{2318}", label: "command", width: 88, height: 64, symbolSize: 25, isLit: keyCmdLit, isFlash: keysFlash)
                keyView(symbol: "\u{21E7}", label: "shift", width: 88, height: 64, symbolSize: 25, isLit: keyShiftLit, isFlash: keysFlash)
                keyView(symbol: "X", label: nil, width: 60, height: 64, symbolSize: 23, isLit: keyXLit, isFlash: keysFlash)
            }
            .opacity(showOutroKeys ? 1 : 0)
            .offset(y: showOutroKeys ? 0 : 8)
            .padding(.top, 36)
            
            Text("Presto.AI lives in your menu bar.\nLook for the wand icon at the top of your screen.")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(WZ.text3)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .opacity(showMenuHint ? 1 : 0)
                .padding(.top, 40)

            // Referral code entry
            VStack(spacing: 8) {
                if !showReferralField {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.3)) { showReferralField = true }
                    }) {
                        Text("Have a referral code?")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(WZ.text4)
                            .underline()
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 8) {
                        TextField("PRESTO-XXXXXX", text: $referralCodeInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(8)
                            .frame(width: 180)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                            .autocorrectionDisabled()

                        Button(action: submitReferralCode) {
                            if isSubmittingReferral {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                            } else {
                                Text("Apply")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.10))
                        .cornerRadius(6)
                        .disabled(referralCodeInput.isEmpty || isSubmittingReferral)
                    }

                    if !referralMessage.isEmpty {
                        Text(referralMessage)
                            .font(.system(size: 12))
                            .foregroundColor(referralIsError ? .red : .green)
                    }
                }
            }
            .opacity(showMenuHint ? 1 : 0)
            .padding(.top, 16)

            Spacer()
        }
        .onAppear { runDoneAnimation() }
    }
    
    private func keyView(symbol: String, label: String?, width: CGFloat, height: CGFloat = 64, symbolSize: CGFloat = 25, isLit: Bool, isFlash: Bool) -> some View {
        VStack(spacing: label != nil ? 4 : 0) {
            Text(symbol)
                .font(.system(size: symbolSize, weight: .regular))
            if let label = label {
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(WZ.text4)
            }
        }
        .foregroundColor(isLit ? Color(white: 0.867) : Color(white: 0.6))
        .frame(width: width, height: height)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFlash ? WZ.keyFlash : (isLit ? WZ.keyActive : WZ.keyBg))
                if isLit {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.07), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                        .padding(-4)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(WZ.keyBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
        .animation(.easeOut(duration: 0.3), value: isLit)
        .animation(.easeInOut(duration: 0.15), value: isFlash)
    }
    
    private func runDoneAnimation() {
        showReadyText = false
        showOutroKeys = false
        keyCmdLit = false
        keyShiftLit = false
        keyXLit = false
        keysFlash = false
        showMenuHint = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.8)) { showReadyText = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.6)) { showOutroKeys = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { keyCmdLit = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation { keyShiftLit = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation { keyXLit = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
            keysFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            keysFlash = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeOut(duration: 0.6)) { showMenuHint = true }
        }
    }
    
    // =========================================================================
    // MARK: - Bottom Actions (pinned above dots, per-step)
    // =========================================================================
    
    private var bottomActions: some View {
        VStack(spacing: 10) {
            switch currentStep {
            case 0:
                // Subtitle sits above the button
                Text("Let's get you set up in under a minute")
                    .font(.system(size: 17, weight: .light))
                    .foregroundColor(WZ.text2)
                    .tracking(0.3)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 8)
                    .padding(.bottom, 6)
                
                // "Let's go"
                actionButton(label: "Let's go", visible: showSubtitle) {
                    UserDefaults.standard.set(OnboardingState.permissionRequested.rawValue, forKey: "onboardingState")
                    withAnimation(.easeInOut(duration: 0.4)) { currentStep = 1 }
                    stepEnteredTime = Date()

                    if CGPreflightScreenCaptureAccess() {
                        // Permission already granted (e.g. from a previous install) —
                        // skip the system prompt and show the granted animation directly.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            triggerGrantedAnimation()
                        }
                    }
                }
                
            case 1:
                if !permissionJustGranted {
                    actionButton(label: "Open System Settings", visible: true) {
                        openScreenRecordingSettings()
                    }

                    Text("Toggle Presto.AI on, then click \"Quit & Reopen\" when prompted")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(WZ.text3)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                
            case 2:
                // "Start using Presto.AI"
                actionButton(label: "Start using Presto.AI", visible: showMenuHint) {
                    UserDefaults.standard.set(OnboardingState.completed.rawValue, forKey: "onboardingState")
                    LaunchAtLoginManager.shared.enable()
                    onComplete()
                }
                
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 60)
        .padding(.bottom, 6)
    }
    
    private func actionButton(label: String, visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.10))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: visible)
    }
    
    // =========================================================================
    // MARK: - Bottom Dots
    // =========================================================================
    
    private var bottomDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i <= currentStep ? Color.white.opacity(0.25) : Color.white.opacity(0.06))
                    .frame(width: 5, height: 5)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .padding(.vertical, 14)
    }
    
    // =========================================================================
    // MARK: - Permission Checks
    // =========================================================================
    
    private func checkPermissions() {
        let granted = CGPreflightScreenCaptureAccess()

        if granted && !screenRecordingGranted {
            // Only auto-advance from step 1 (permission request).
            // Never skip the welcome page (step 0) — the user must click "Let's go" first.
            if currentStep == 1 {
                triggerGrantedAnimation()
            }
            return
        }

        if granted { screenRecordingGranted = true }
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkPermissions()
        }
    }
    
    // MARK: - Referral Code Submission

    private func submitReferralCode() {
        let code = referralCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        isSubmittingReferral = true
        referralMessage = ""

        Task {
            do {
                let deviceID = AppStateManager.shared.deviceID
                try await APIService.shared.claimReferralCode(deviceID: deviceID, code: code)
                await MainActor.run {
                    isSubmittingReferral = false
                    referralIsError = false
                    referralMessage = "Referral code applied!"
                }
            } catch {
                await MainActor.run {
                    isSubmittingReferral = false
                    referralIsError = true
                    referralMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Deep Links

    private func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
    }
}
