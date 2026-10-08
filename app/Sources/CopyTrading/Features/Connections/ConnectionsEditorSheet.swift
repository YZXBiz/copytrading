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
                    remove: { removeAccount(id) },
                    focusesEntryTolerance: model.editorFocusesEntryTolerance,
                    failedCheck: failedCheck(.account(model.setupDraft.accounts[index].name.trimmed)),
                    check: { [model] in
                        guard let account = model.setupDraft.accounts.first(where: { $0.id == id }) else { return nil }
                        return await model.checkConnection(.account(account.name.trimmed))
                    },
                    saveLimits: { [model] in await model.saveLimitOnlyChanges() },
                    limitsError: model.message
                )
                .onChange(of: model.setupDraft.accounts[index].name) { oldName, newName in
                    model.renameAccountReferences(from: oldName.trimmed, to: newName.trimmed)
                }
                .onAppear { model.limitsSavedAccountIDs.remove(model.setupDraft.accounts[index].name.trimmed) }
                .onDisappear { model.editorFocusesEntryTolerance = false }
            }
        case .route(let id):
            if let index = model.setupDraft.routes.firstIndex(where: { $0.id == id }) {
                RouteEditorSheet(
                    route: $model.setupDraft.routes[index],
                    accountIDs: model.setupDraft.accountChoices(for: model.setupDraft.routes[index]),
                    policies: Dictionary(
                        model.setupDraft.accounts.map { ($0.name.trimmed, $0.policy) },
                        uniquingKeysWith: { first, _ in first }),
                    channelIDs: model.setupDraft.sourceChannelIDs,
                    learn: learn,
                    replay: { try await model.replayPosts(for: $0, in: model.setupDraft) },
                    remove: { removeGuru(id) }
                )
            }
        }
    }

    private func failedCheck(_ subject: ConnectionCheckSubject) -> TradingCapabilityCheck? {
        guard let check = model.connectionCheckResult(subject)?.check, check.state == .failed else { return nil }
        return check
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
