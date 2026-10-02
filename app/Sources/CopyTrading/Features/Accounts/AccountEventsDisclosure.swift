import DesktopCore
import SwiftUI

struct AccountEventsDisclosure: View {
    let accountID: String
    let model: AppModel
    let feature: AccountFeatureModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(L10n.string("Account history"), isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                if let error = feature.errors["events:\(accountID)"] {
                    Callout(error, tone: .critical)
                        .accessibilityLabel(L10n.string("Account events error: %@", error))
                }
                let events = feature.events[accountID] ?? []
                if events.isEmpty {
                    Text(L10n.string("No history loaded."))
                        .foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(event.title)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 12)
                        Text(Humanize.timestamp(event.at))
                            .foregroundStyle(Palette.tertiaryInk)
                            .monospacedDigit()
                    }
                    .font(.callout)
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
                    .accessibilityElement(children: .combine)
                }
                if feature.eventCursors[accountID] != nil {
                    Button(L10n.string("Load Older History"), action: loadMore)
                        .buttonStyle(.borderless)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded { load() }
        }
    }

    private func load() {
        Task { await feature.loadEvents(accountID: accountID, using: model.accountActions()) }
    }

    private func loadMore() {
        Task { await feature.loadEvents(accountID: accountID, more: true, using: model.accountActions()) }
    }
}
