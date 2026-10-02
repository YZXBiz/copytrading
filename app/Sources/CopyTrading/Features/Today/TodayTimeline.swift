import DesktopCore
import SwiftUI

/// Today's posts, newest first, each with what every account did about it.
struct TodayTimeline: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel
    @State private var hoveredID: SourceActivity.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let limit = 8

    private var today: [SourceActivity] {
        feature.activity.filter(\.isToday)
    }

    var body: some View {
        let directory = GuruDirectory(model.savedTradingConfiguration)
        let shown = Array(today.prefix(Self.limit))
        PageSection("What happened today", symbol: "text.bubble") {
            Button(L10n.string("All Activity"), action: openActivity)
                .buttonStyle(.link)
        } content: {
            if today.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(shown) { item in
                        Button {
                            open(item)
                        } label: {
                            ActivityInboxRow(item: item, guruName: directory.name(for: item.guruID), preview: directory.preview(of: item))
                                .padding(14)
                                .background(hoveredID == item.id ? Palette.hover : Palette.page, in: .rect(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Palette.hairline, lineWidth: 0.7)
                                        .allowsHitTesting(false)
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(QuietPressButtonStyle())
                        .onHover { isHovering in
                            hoveredID = isHovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
                        }
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredID)
                        .accessibilityHint(L10n.string("Shows this post in Activity"))
                    }
                }
                if today.count > Self.limit {
                    Text(L10n.string("%lld more today in Activity", Int64(today.count - Self.limit)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor private var emptyText: String {
        let names = GuruDirectory(model.savedTradingConfiguration).gurus.map(\.name)
        let who = names.isEmpty ? L10n.string("your gurus") : localizedList(names)
        return model.tradingStatus?.state == .running
            ? L10n.string("No posts yet today. New calls from %@ appear here within seconds.", who)
            : L10n.string("No posts today. Start copying to follow %@.", who)
    }

    @MainActor private func localizedList(_ values: [String]) -> String {
        guard let last = values.last else { return "" }
        guard values.count > 1 else { return last }
        let prefix = Humanize.joined(Array(values.dropLast()))
        return values.count == 2
            ? L10n.string("%@ and %@", prefix, last)
            : L10n.string("%@, and %@", prefix, last)
    }

    private func open(_ item: SourceActivity) {
        feature.focusedActivityID = item.id
        model.selectedScreen = .activity
    }

    private func openActivity() {
        model.selectedScreen = .activity
    }
}
