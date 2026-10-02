import SwiftUI

/// The frosted panel Connections opens over its page:
/// a header on the app's chart paper, a serif title with an italic second line, and its content.
struct ConnectionPanel<Content: View>: View {
    let lead: String
    let emphasis: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            SerifTitle(lead: lead, emphasis: emphasis, alignment: .center)
                .font(DesignTokens.panelSerif)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.top, 44)
                .padding(.bottom, 30)
                .padding(.horizontal, 28)

            content
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
        }
        .frame(width: 440)
        .background { backdrop }
        .clipShape(.rect(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    contrast == .increased ? Palette.secondaryInk : .white.opacity(colorScheme == .dark ? 0.1 : 0.75),
                    lineWidth: 1)
        }
    }

    private var backdrop: some View {
        ZStack(alignment: .top) {
            if reduceTransparency || contrast == .increased {
                Palette.page
            } else {
                Rectangle().fill(.regularMaterial)
                ChartPaperBackdrop(focus: UnitPoint(x: 0.5, y: 0), gridSpacing: 22)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0), .init(color: .black.opacity(0.35), location: 0.45),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    }
                    .opacity(0.9)
            }
        }
        .accessibilityHidden(true)
    }
}
