import DesktopCore
import Foundation
import Testing

/// Touch ID guards the orders the owner sends by hand (ADR-0008): always for a live account, and
/// for a paper account only when it asked to approve every order.
@MainActor
func runOrderApprovalTests() async throws {
    try await touchIDIsAskedOnlyWhereOrdersNeedIt()
    try await aRefusedTouchIDSendsNothing()
}

/// Approves every prompt, or only the first (opening the window) and refuses the rest.
private actor CountingAuthenticator: AppOwnerAuthenticator {
    private(set) var prompts: [String] = []
    private let approvesOnlyTheFirst: Bool

    init(approvesOnlyTheFirst: Bool = false) { self.approvesOnlyTheFirst = approvesOnlyTheFirst }

    func authenticate(localizedReason: String) async throws {
        if approvesOnlyTheFirst, !prompts.isEmpty { throw AppUnlockError.authenticationCancelled }
        prompts.append(localizedReason)
    }

    func invalidate() async {}
}

private func configuration() -> TradingConfiguration {
    var asking = TradingAccountPolicy()
    asking.approveOrders = true
    return TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["1"]),
        provider: TradingProviderConfiguration(name: .deepseek, model: "deepseek-flash"),
        accounts: [
            TradingAccountConfiguration(id: "plain-paper", environment: .paper),
            TradingAccountConfiguration(id: "asking-paper", environment: .paper, policy: asking),
            TradingAccountConfiguration(id: "plain-live", environment: .live),
        ],
        profiles: [], routes: [])
}

@MainActor
private func openedModel(approving authenticator: CountingAuthenticator) async throws -> AppModel {
    let unlock = AppUnlock(authenticator: authenticator)
    try await unlock.openWindow(UUID())
    let model = AppModel(appUnlock: unlock)
    model.savedTradingConfiguration = configuration()
    return model
}

@MainActor
private func touchIDIsAskedOnlyWhereOrdersNeedIt() async throws {
    let authenticator = CountingAuthenticator()
    let model = try await openedModel(approving: authenticator)
    // The window's own opening prompt is not an order approval.
    let opening = await authenticator.prompts.count

    try await model.confirmOrders(for: ["plain-paper"], reason: "send")
    try #require(await authenticator.prompts.count == opening, "a plain paper account was asked for Touch ID")

    try await model.confirmOrders(for: ["asking-paper"], reason: "send")
    try #require(await authenticator.prompts.count == opening + 1, "an approving paper account was not asked")

    try await model.confirmOrders(for: ["plain-live"], reason: "send")
    try #require(await authenticator.prompts.count == opening + 2, "a live account was not asked")

    try await model.confirmOrders(for: ["plain-paper", "asking-paper"], reason: "send")
    try #require(await authenticator.prompts.count == opening + 3, "one batch asked more than once")

    try #require(!model.approvesOrders(accountID: "plain-paper"), "a plain account reads as approving")
    try #require(model.approvesOrders(accountID: "asking-paper"), "an approving account reads as plain")
    try #require(!model.requiresOwnerForOrders(accountID: "missing"), "an unknown account asked for Touch ID")
}

@MainActor
private func aRefusedTouchIDSendsNothing() async throws {
    let model = try await openedModel(approving: CountingAuthenticator(approvesOnlyTheFirst: true))

    do {
        try await model.confirmOrders(for: ["asking-paper"], reason: "send")
    } catch AppUnlockError.authenticationCancelled {
        return  // The owner did not confirm, so the caller sends nothing.
    }
    throw VerificationFailure(description: "a refused Touch ID still let the orders through")
}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}
