import SwiftUI
import AppKit

// MARK: - Paywall Data Model

struct PaywallInfo {
    let canUseReferral: Bool
    let referralCode: String?
    let qualifiedCount: Int
    let needed: Int
    let subscribePrice: String
    let checkoutURL: String
    let rewardExpiresAt: String?
}

// MARK: - Paywall View

struct PaywallView: View {
    let info: PaywallInfo
    let onDismiss: () -> Void
    let onCreateReferralCode: () -> Void
    let onSubscribe: () -> Void

    @State private var linkCopied = false
    @State private var referralCode: String?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Unlock Your Full Potential")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.text1(colorScheme))
                .padding(.top, 16)
                .padding(.bottom, 6)

            Text("Choose how to continue your experience")
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(colorScheme))
                .padding(.bottom, 20)

            if info.canUseReferral {
                dualLayout
            } else {
                subscribeOnlyLayout
            }
        }
        .padding(.bottom, 24)
        .frame(width: info.canUseReferral ? 560 : 420, height: 420)
        .background(Theme.bg(colorScheme))
        .onAppear {
            referralCode = info.referralCode
        }
    }

    // MARK: - Dual Layout (Subscribe + Referral)

    private var dualLayout: some View {
        HStack(spacing: 16) {
            subscribeCard
            referralCard
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
    }

    // MARK: - Subscribe Only Layout

    private var subscribeOnlyLayout: some View {
        subscribeCard
            .frame(maxWidth: 280)
            .padding(.horizontal, 40)
    }

    // MARK: - Subscribe Card

    private var subscribeCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundColor(Theme.text1(colorScheme))

            Text("Unlimited Analyses")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))

            Text(info.subscribePrice)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.text1(colorScheme))

            // Feature bullets
            VStack(alignment: .leading, spacing: 5) {
                featureBullet("End-to-end depth reports")
                featureBullet("Advanced data points")
                featureBullet("Priority support")
            }
            .padding(.bottom, 4)

            Spacer(minLength: 0)

            Button(action: onSubscribe) {
                Text("Start Full Access")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text1(colorScheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface(colorScheme))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border(colorScheme), lineWidth: 1)
        )
    }

    private func featureBullet(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.text2(colorScheme))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Theme.text2(colorScheme))
        }
    }

    // MARK: - Referral Card

    private var referralCard: some View {
        let remaining = info.needed - info.qualifiedCount

        return VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 28))
                .foregroundColor(Theme.text1(colorScheme))

            Text("Get 1 Free Month")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.text1(colorScheme))

            Text("Refer 3 friends to join and explore")
                .font(.system(size: 13))
                .foregroundColor(Theme.text2(colorScheme))
                .multilineTextAlignment(.center)

            // Progress icons
            HStack(spacing: 8) {
                ForEach(0..<info.needed, id: \.self) { i in
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(i < info.qualifiedCount ? .green : Theme.subtleBorder(colorScheme))
                }
            }

            VStack(spacing: 2) {
                Text("\(remaining) invite\(remaining == 1 ? "" : "s") remaining")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text2(colorScheme))
                Text("\(remaining) invite\(remaining == 1 ? "" : "s") remaining to claim reward")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text2(colorScheme).opacity(0.7))
            }
            .padding(.bottom, 4)

            Spacer(minLength: 0)

            Button(action: {
                if let code = referralCode {
                    copyReferralLink(code: code)
                } else {
                    onCreateReferralCode()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: linkCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                    Text(linkCopied ? "Link copied!" : "Copy Invitation Link")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(Theme.text1(colorScheme))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Theme.inputBg(colorScheme))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.subtleBorder(colorScheme), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface(colorScheme))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border(colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func copyReferralLink(code: String) {
        let link = "https://prestoai.app/r/\(code)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        withAnimation { linkCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { linkCopied = false }
        }
    }

    func updateReferralCode(_ code: String) {
        referralCode = code
        copyReferralLink(code: code)
    }
}

// MARK: - Paywall Controller

class PaywallController {
    private var window: NSWindow?

    func show(info: PaywallInfo, onSubscribe: @escaping () -> Void) {
        let view = PaywallView(
            info: info,
            onDismiss: { [weak self] in
                self?.window?.close()
                self?.window = nil
            },
            onCreateReferralCode: {
                Task {
                    do {
                        let deviceID = AppStateManager.shared.deviceID
                        let result = try await APIService.shared.createReferralCode(deviceID: deviceID)
                        await MainActor.run {
                            // Re-show with updated code
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("https://prestoai.app/r/\(result.code)", forType: .string)
                        }
                    } catch {
                        print("[Paywall] Failed to create referral code: \(error)")
                    }
                }
            },
            onSubscribe: { [weak self] in
                self?.window?.close()
                self?.window = nil
                onSubscribe()
            }
        )

        let size = info.canUseReferral
            ? NSSize(width: 560, height: 420)
            : NSSize(width: 420, height: 420)
        let panel = makePrestoPanel(size: size, title: "")
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}
