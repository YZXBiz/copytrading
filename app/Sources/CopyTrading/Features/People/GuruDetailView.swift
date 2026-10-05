import DesktopCore
import SwiftUI

struct GuruDetailView: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel
    let guru: GuruDirectory.Guru
    let openPost: (SourceActivity) -> Void
    let edit: () -> Void
    @State private var hoveredPostID: SourceActivity.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor private var stats: GuruStats { GuruStats(guruID: guru.id, activity: feature.activity) }

    private var recent: [SourceActivity] {
        Array(feature.activity.filter { $0.guruID == guru.id }.prefix(12))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.panelSpacing) {
                HStack(spacing: 14) {
                    GuruMonogram(name: guru.name, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guru.name)
                            .font(DesignTokens.personTitle)
                        Text(L10n.string("Posts in Discord channel %@", guru.channels.joined(separator: ", ")))
                            .font(DesignTokens.bodyText)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(L10n.string("Edit Guru…"), systemImage: "pencil", action: edit)
                }

                HStack(alignment: .top, spacing: 16) {
                    figure("Posts", stats.posts)
                    figure("Trades called", stats.trades)
                    figure("Orders filled", stats.filled)
                    figure("Skipped", stats.skipped)
                    figure("Need review", stats.needsReview)
                }
                Text(L10n.string("Counted from the %@ CopyTrading has loaded.", Humanize.count(feature.activity.count, "most recent post")))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("Copies into")
                    ForEach(guru.destinations) { destination in
                        HStack(spacing: 8) {
                            Text(destination.accountID)
                                .fontWeight(.medium)
                            if let environment = environment(of: destination.accountID) {
                                EnvironmentBadge(environment: environment)
                            }
                            Spacer()
                            Text(sizing(destination))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("Recent calls")
                    if recent.isEmpty {
                        Text(L10n.string("No posts from %@ have been loaded yet.", guru.name))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(recent) { item in
                        Button {
                            openPost(item)
                        } label: {
                            ActivityInboxRow(item: item, guruName: guru.name, preview: item.readableText(dropping: guru.prefix))
                                .padding(14)
                                .background(hoveredPostID == item.id ? Palette.hover : Palette.page, in: .rect(cornerRadius: 10))
                                .contentShape(.rect(cornerRadius: 10))
                        }
                        .buttonStyle(QuietPressButtonStyle())
                        .onHover { hoveredPostID = $0 ? item.id : nil }
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredPostID)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: DesignTokens.readingContentMaxWidth, alignment: .leading)
        }
        .background(Palette.canvas)
    }

    private func figure(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(DesignTokens.rowTitle)
                .monospacedDigit()
            Text(L10n.string(title))
                .font(DesignTokens.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func environment(of accountID: String) -> TradingEnvironment? {
        model.savedTradingConfiguration?.accounts.first { $0.id == accountID }?.environment
    }

    @MainActor private func sizing(_ destination: TradingRouteConnection) -> String {
        let amount =
            Decimal(engine: destination.fullPositionUSD)?.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
            ?? destination.fullPositionUSD
        return L10n.string("Full position %@: each call buys the guru's share of it", amount)
    }
}
