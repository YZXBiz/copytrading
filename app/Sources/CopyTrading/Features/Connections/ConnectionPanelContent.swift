import DesktopCore
import SwiftUI

/// What an open Connections panel shows: one service's settings.
struct ConnectionPanelContent: View {
    let page: ConnectionPanelPage
    @Bindable var model: AppModel
    let close: () -> Void

    var body: some View {
        switch page {
        case .editor(let kind):
            ConnectionPanel(lead: lead(for: kind), emphasis: emphasis(for: kind)) {
                ConnectionEditor(kind: kind, model: model, done: close)
            }
        }
    }

    @MainActor private func lead(for kind: ConnectionKind) -> String {
        switch kind {
        case .discord: L10n.string("Read Calls From")
        case .interpreter: L10n.string("Read Posts With")
        case .alerts: L10n.string("Send Alerts To")
        }
    }

    private func emphasis(for kind: ConnectionKind) -> String {
        switch kind {
        case .discord: "Discord"
        case .interpreter: model.setupDraft.provider.shortTitle
        case .alerts: "Telegram"
        }
    }
}
