import SwiftUI

/// One account's result for a post, printed as a till receipt: who it is for and how it ended at
/// the top, the takeaway, the numbers as receipt lines, the price ruler, and a rubber stamp when
/// the call was not copied. It prints once, out of its slot, when the post opens.
struct PostReceipt: View {
    let account: String
    let isLive: Bool
    let result: ActivityCardOutcome.Result
    let tone: StatusTone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var printed = false

    private var stamp: String {
        switch tone {
        case .positive: L10n.string("Copied")
        case .caution: L10n.string("Waiting")
        case .neutral: L10n.string("Working")
        default: L10n.string("Not copied")
        }
    }

    /// A call that went nowhere says why on a stamp; anything else keeps its note as a line.
    private var isRefused: Bool { tone == .inactive || tone == .critical }

    var body: some View {
        VStack(spacing: 0) {
            // The slot the receipt prints from.
            Capsule()
                .fill(Palette.ink)
                .frame(height: 10)
                .overlay(Capsule().fill(Palette.page).padding(.horizontal, 14).frame(height: 3))
                .zIndex(1)
            paper
                .padding(.horizontal, 14)
                .offset(y: -3)
                .mask(alignment: .top) {
                    GeometryReader { proxy in
                        Rectangle().frame(height: proxy.size.height * (printed ? 1 : 0))
                    }
                    .padding(.bottom, -12)
                }
        }
        .onAppear {
            guard !printed else { return }
            if reduceMotion {
                printed = true
            } else {
                withAnimation(.easeOut(duration: 0.7)) { printed = true }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(stamp.uppercased())
                    .font(DesignTokens.eyebrow)
                    .tracking(DesignTokens.eyebrowTracking)
                    .foregroundStyle(tone == .positive ? Palette.ink : Palette.tertiaryInk)
                Spacer(minLength: 8)
                Text(L10n.string("%@ · %@", account, L10n.string(isLive ? "Live" : "Paper")).uppercased())
                    .font(DesignTokens.eyebrow)
                    .tracking(DesignTokens.eyebrowTracking)
                    .foregroundStyle(isLive ? Color.orange : Palette.tertiaryInk)
                    .lineLimit(1)
            }
            Text(result.headline)
                .font(DisplayFont.font(size: 22, weight: .medium, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if let prices = result.prices {
                tear
                PriceRuler(points: prices)
            }
            if !result.facts.isEmpty {
                tear
                VStack(spacing: 8) {
                    ForEach(Array(result.facts.enumerated()), id: \.offset) { _, fact in
                        HStack(alignment: .firstTextBaseline) {
                            Text(fact.label).foregroundStyle(Palette.tertiaryInk)
                            Spacer(minLength: 12)
                            Text(fact.value).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
                        }
                    }
                }
                .font(.system(size: 13, design: .monospaced))
            }
            if let note = result.note {
                if isRefused {
                    RubberStamp(text: note)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } else {
                    Text(note)
                        .font(DesignTokens.activityBody)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .background(Palette.page)
        .overlay(Rectangle().stroke(Palette.ink, lineWidth: 1.4))
        .overlay(alignment: .bottom) {
            ReceiptEdge()
                .fill(Palette.page)
                .overlay(ReceiptEdge().stroke(Palette.ink, lineWidth: 1.4))
                .frame(height: 9)
                .offset(y: 8)
        }
        .padding(.bottom, 9)
    }

    /// The dashed rule a till prints between sections.
    private var tear: some View {
        ReceiptRule()
            .stroke(Palette.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
    }
}
