import DesktopCore
import Foundation

/// What the assistant answers with: the model the owner already set up for reading posts.
extension AppModel {
    /// The saved interpreter and its key, else a complete one still being typed in Connections;
    /// nil when neither can answer.
    static func assistantInterpreter(
        saved: (configuration: TradingConfiguration, secrets: TradingSecrets)?, draft: ConnectionsDraft
    ) -> (TradingProviderConfiguration, String)? {
        if let saved {
            let provider = saved.configuration.provider
            let key = providerKey(entered: "", for: provider.name, saved: saved)
            if isUsableInterpreter(provider), !provider.name.requiresAPIKey || !key.isEmpty { return (provider, key) }
        }
        let provider = draft.providerConfiguration
        let key = providerKey(entered: draft.providerAPIKey, for: draft.provider, saved: saved)
        guard isUsableInterpreter(provider), !provider.name.requiresAPIKey || !key.isEmpty else { return nil }
        return (provider, key)
    }

    static func isUsableInterpreter(_ provider: TradingProviderConfiguration) -> Bool {
        !provider.model.trimmed.isEmpty && provider.baseURLProblem == nil
    }

    /// The same answer as `assistantInterpreter`, without reading the Keychain, for the panel to ask on every redraw.
    var assistantHasModel: Bool {
        guard isTradingUnlocked else { return false }
        if let provider = savedTradingConfiguration?.provider, Self.isUsableInterpreter(provider),
            !provider.name.requiresAPIKey || hasTradingSecrets
        {
            return true
        }
        return Self.isUsableInterpreter(setupDraft.providerConfiguration) && interpreterHasKey
    }

    /// The saved interpreter's key comes from the Keychain, so this runs once per question.
    func assistantInterpreter() -> (TradingProviderConfiguration, String)? {
        guard isTradingUnlocked else { return nil }
        return Self.assistantInterpreter(saved: savedTradingSnapshot(), draft: setupDraft)
    }

    /// What the owner is looking at, so "this post" and "this guru" mean something to the assistant,
    /// the gurus by name, and the app's language, which the answer falls back to when the question
    /// doesn't settle it.
    func assistantContext(selectedPost: SourceActivity?) -> AssistantAskContext {
        AssistantAskContext(
            screen: selectedScreen.rawValue,
            selectedSourceID: selectedScreen == .activity ? selectedPost?.sourceID : nil,
            selectedGuruID: selectedScreen == .people ? openGuruID : nil,
            language: AppLanguagePreference.shared.language.rawValue,
            gurus: assistantGurus)
    }

    /// Every guru by the name the owner gave them: the saved setup's, else the one being set up.
    var assistantGurus: [AssistantGuru] {
        let named: [(String, String)] =
            if let profiles = savedTradingConfiguration?.profiles, !profiles.isEmpty {
                profiles.map { ($0.guruID, $0.displayName) }
            } else {
                setupDraft.routes.map { ($0.guruID.trimmed, $0.displayName.trimmed) }
            }
        var seen = Set<String>()
        return named.compactMap { id, name in
            // The engine reads ids as the setup stores them and names of up to 100 characters.
            guard id.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil, !name.isEmpty,
                seen.insert(id).inserted
            else { return nil }
            return AssistantGuru(id: id, name: String(name.prefix(100)))
        }
    }

    /// Opens what an answer points at: the post in Activity, the account in Accounts, or the guru's sheet in People.
    func follow(_ link: AssistantLink, activity: [SourceActivity], focusPost: (SourceActivity.ID) -> Void) {
        switch link.kind {
        case "post":
            if let post = activity.first(where: { $0.sourceID == link.id }) { focusPost(post.id) }
            selectedScreen = .activity
        case "account":
            requestedAccountID = link.id
            selectedScreen = .accounts
        case "guru":
            requestedGuruID = link.id
            selectedScreen = .people
        default:
            break
        }
    }

    func connectAssistant() {
        assistant.connect(
            operations: { [weak self] in self?.agentEngineActions() },
            interpreter: { [weak self] in self?.assistantInterpreter() },
            hasModel: { [weak self] in self?.assistantHasModel ?? false },
            refreshProposals: { [weak self] in await self?.refreshAssistantProposals() })
    }
}
