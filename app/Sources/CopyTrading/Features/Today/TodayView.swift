import DesktopCore
import SwiftUI

/// The first screen: did I make or lose money today, what happened, and am I inside my limits.
struct TodayView: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(
                max(0, geometry.size.width - DesignTokens.pagePadding * 2),
                DesignTokens.todayContentMaxWidth
            )
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.panelSpacing) {
                    PageHeader(L10n.string("Today"), subtitle: subtitle)
                    if let configuration = model.savedTradingConfiguration {
                        if showsLiveCard {
                            CopyingLiveCard(model: model, feature: feature)
                                .transition(.opacity)
                        }
                        PortfolioPanel(model: model, feature: feature)
                        if contentWidth >= DesignTokens.todayTimelineMinWidth + DesignTokens.todayLimitsWidth
                            + DesignTokens.pageSectionSpacing
                        {
                            HStack(alignment: .top, spacing: DesignTokens.pageSectionSpacing) {
                                TodayTimeline(model: model, feature: feature)
                                    .frame(maxWidth: DesignTokens.readingContentMaxWidth, alignment: .topLeading)
                                LimitsPanel(model: model, feature: feature, configuration: configuration)
                                    .frame(width: DesignTokens.todayLimitsWidth)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LimitsPanel(model: model, feature: feature, configuration: configuration)
                            Divider()
                            TodayTimeline(model: model, feature: feature)
                        }
                    } else {
                        TodaySetupPrompt(model: model)
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding([.horizontal, .bottom], DesignTokens.pagePadding)
                .padding(.top, DesignTokens.pageTopPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle(L10n.string("Today"))
    }

    /// The "you're copying" card shows from a new setup's start until its first post arrives.
    private var showsLiveCard: Bool {
        guard let started = model.copyingStartedAt else { return false }
        let state = model.tradingStatus?.state
        guard state == .running || state == .starting || state == .degraded else { return false }
        return !feature.activity.contains { (Humanize.date($0.capturedAt) ?? .distantPast) > started }
    }

    @MainActor private var subtitle: String {
        let date = Date.now.formatted(
            .dateTime.weekday(.wide).month(.wide).day().locale(AppLanguagePreference.shared.language.locale)
        )
        let names = GuruDirectory(model.savedTradingConfiguration).gurus.map(\.name)
        guard !names.isEmpty else { return date }
        let people: String
        switch names.count {
        case 1: people = names[0]
        case 2: people = L10n.string("%@ and %@", names[0], names[1])
        default: people = L10n.string("%lld people", Int64(names.count))
        }
        return L10n.string("%@ · %@", date, people)
    }
}
