import DesktopCore
import SwiftUI

/// Resolves an editing target to a binding into the draft, so the sheet edits the account or guru
/// in place, from whichever screen opened it.
struct ConnectionsEditorSheet: View {
    let target: ConnectionsEditingTarget
    @Bindable var model: AppModel

    var body: some View {
        switch target {
        case .account(let id):
            if let index = model.setupDraft.accounts.firstIndex(where: { $0.id == id }) {
                AccountEditorSheet(
                    account: $model.setupDraft.accounts[index],
                    savedAccountIDs: model.savedKeyAccountIDs,
                    remove: { removeAccount(id) }
                )
                .onChange(of: model.setupDraft.accounts[index].name) { oldName, newName in
                    model.renameAccountReferences(from: oldName.trimmed, to: newName.trimmed)
                }
            }
        case .route(let id):
            if let index = model.setupDraft.routes.firstIndex(where: { $0.id == id }) {
                RouteEditorSheet(
                    route: $model.setupDraft.routes[index],
                    accountIDs: model.setupDraft.accountIDs,
                    channelIDs: model.setupDraft.sourceChannelIDs,
                    learn: learn,
                    remove: { removeGuru(id) }
                )
            }
        }
    }

    private func learn(_ route: TradingRouteDraft) async throws -> LearnedGuruPlaybook {
        try await model.learnPlaybook(for: route, in: model.setupDraft)
    }

    private func removeAccount(_ id: UUID) {
        model.setupEditor = nil
        model.setupDraft.accounts.removeAll { $0.id == id }
    }

    private func removeGuru(_ id: UUID) {
        model.setupEditor = nil
        model.setupDraft.routes.removeAll { $0.id == id }
    }
}
