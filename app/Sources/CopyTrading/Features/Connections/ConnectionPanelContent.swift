import DesktopCore
import SwiftUI

/// What an open Connections panel shows: one service's settings.
struct ConnectionPanelContent: View {
    let page: ConnectionPanelPage
    @Bindable var model: AppModel
    let close: () -> Void
    /// Whether the service was set up when the sheet opened, so its title holds while you type.
    @State private var openedSetUp: Bool?

    var body: some View {
        switch page {
        case .editor(let kind):
            ConnectionPanel(
                title: title(for: kind), brand: brand(for: kind), close: close, escapeCloses: !model.assistant.isOpen
            ) {
                ConnectionEditor(kind: kind, model: model, isNew: !(openedSetUp ?? isSetUp(kind)), done: close)
            }
            .onAppear { openedSetUp = openedSetUp ?? isSetUp(kind) }
        }
    }

    /// "Connect to DeepSeek" before the service is set up; just its name after.
    @MainActor private func title(for kind: ConnectionKind) -> String {
        let name =
            switch kind {
            case .discord: "Discord"
            case .interpreter: L10n.string(model.setupDraft.provider.title)
            case .alerts: model.setupDraft.notificationService == .discord ? "Discord" : "Telegram"
            }
        return (openedSetUp ?? isSetUp(kind)) ? name : L10n.string("Connect to %@", name)
    }

    private func isSetUp(_ kind: ConnectionKind) -> Bool {
        ConnectionSummary.of(kind, in: model) != nil
    }

    private func brand(for kind: ConnectionKind) -> String? {
        switch kind {
        case .discord: "discord"
        case .interpreter: model.setupDraft.provider.brandIcon
        case .alerts: model.setupDraft.notificationService.brandIcon
        }
    }
}

#Preview("Connect to DeepSeek") {
    let model = AppModel()
    model.setupDraft.provider = .deepseek
    model.setupDraft.modelName = "deepseek-flash"
    return ConnectionPanelContent(page: .editor(.interpreter), model: model, close: {})
        .padding(40)
}

#Preview("Connect to Discord alerts") {
    let model = AppModel()
    model.setupDraft.notificationService = .discord
    return ConnectionPanelContent(page: .editor(.alerts), model: model, close: {})
        .padding(40)
}
