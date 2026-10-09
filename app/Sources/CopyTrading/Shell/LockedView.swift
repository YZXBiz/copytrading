import SwiftUI

/// The locked window as a quiet hero: the app's name in the display face, a line on what unlocking
/// opens, the walker on its ground, and one Unlock.
struct LockedView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            Text(L10n.string("CopyTrading"))
                .font(DesignTokens.documentTitle)
                .tracking(DesignTokens.documentTitleTracking)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 6) {
                Text(L10n.string("CopyTrading is locked"))
                    .foregroundStyle(Palette.tertiaryInk)
                if let runtimeStopMessage = model.runtimeStopMessage {
                    Text(runtimeStopMessage)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                if let accessMessage = model.accessMessage {
                    Text(accessMessage)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(L10n.string("Authentication status: %@", accessMessage))
                }
            }
            .font(DesignTokens.lede)
            .tracking(DesignTokens.ledeTracking)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
            .padding(.horizontal, 40)
            InkGround(height: 64)
                .overlay(alignment: .bottom) {
                    InkWalker()
                        .padding(.bottom, 3)
                }
                .frame(width: 380)
                .padding(.top, 36)
            Group {
                if model.isUnlockingTrading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.string("Waiting for macOS authentication…"))
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                    .frame(minHeight: 28)
                } else {
                    Button(L10n.string("Unlock"), systemImage: "touchid", action: unlock)
                        .buttonStyle(PageButtonStyle(isProminent: true, horizontalPadding: 18))
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("app.unlock")
                }
            }
            .padding(.top, 28)
            Spacer(minLength: 40)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.page)
    }

    private func unlock() {
        Task { await model.unlockTrading() }
    }
}
