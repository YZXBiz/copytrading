import DesktopCore
import Foundation
import Observation

protocol AccountOperations: Sendable {
    func accounts(beforeAccountID: String?, limit: Int) async throws -> AccountOverviewPage
    func sourceActivity(beforeSeq: Int?, limit: Int) async throws -> SourceActivityPage
    func accountFeed(accountID: String, beforeSeq: Int?, limit: Int) async throws -> AccountFeedPage
    func controlAccount(_ command: AccountControlCommand) async throws -> AccountControlResult
    func equityHistory(accountID: String, window: EquityHistoryWindow) async throws -> EquityHistory?
    func resolveOwnership(accountID: String, resolution: OwnershipResolutionRequest) async throws -> OwnershipResolution
}

extension EngineActions: AccountOperations {}

@MainActor
@Observable
final class AccountFeatureModel {
    private(set) var accounts: [AccountOverview] = []
    private(set) var nextAccountCursor: String?
    private(set) var isLoadingMoreAccounts = false
    private(set) var activity: [SourceActivity] = []
    private(set) var unavailableAccounts: [AccountUnavailable] = []
    private(set) var nextActivityCursor: Int?
    /// Each account's feed, newest first, and where its next older page starts.
    private(set) var feeds: [String: [AccountFeedItem]] = [:]
    private(set) var feedCursors: [String: Int] = [:]
    private(set) var pendingAccounts: Set<String> = []
    private(set) var isRefreshing = false
    private(set) var errors: [String: String] = [:]
    /// When accounts and activity were last read successfully; the toolbar shows its age.
    private(set) var lastUpdatedAt: Date?
    private(set) var histories: [String: EquityHistory] = [:]
    private(set) var historyWindow: EquityHistoryWindow = .today
    private var retryCommands: [String: AccountControlCommand] = [:]
    private var privateAccessGeneration: UUID?
    private var loadedAccountPageCount = 0
    private let accountPageSize = 25

    func authorizePrivateEvidence() {
        guard privateAccessGeneration == nil else { return }
        privateAccessGeneration = UUID()
    }

    func refresh(using actions: (any AccountOperations)?) async {
        guard let actions, let generation = privateAccessGeneration, !isRefreshing else { return }
        isRefreshing = true
        defer {
            if isCurrent(generation) { isRefreshing = false }
        }
        do {
            let accountPage = try await actions.accounts(
                beforeAccountID: nil, limit: accountPageSize
            )
            guard isCurrent(generation) else { return }
            accounts = accountPage.items
            nextAccountCursor = accountPage.nextBeforeAccountID
            loadedAccountPageCount = 1
            unavailableAccounts = []
            recordUnavailable(accountPage.unavailableAccounts)

            let page = try await actions.sourceActivity(beforeSeq: nil, limit: 25)
            guard isCurrent(generation) else { return }
            activity = page.items
            nextActivityCursor = page.nextBeforeSeq
            recordUnavailable(page.unavailableAccounts)
            errors.removeValue(forKey: "read")
            lastUpdatedAt = .now
        } catch {
            guard isCurrent(generation) else { return }
            errors["read"] = error.localizedDescription
        }
    }

    /// Re-reads only the newest posts, for the fast tick while a post is in flight; older pages
    /// already loaded stay.
    func refreshActivity(using actions: (any AccountOperations)?) async {
        guard let actions, let generation = privateAccessGeneration, !isRefreshing else { return }
        do {
            let page = try await actions.sourceActivity(beforeSeq: nil, limit: 25)
            guard isCurrent(generation) else { return }
            activity = Self.merged(page.items, into: activity)
            errors.removeValue(forKey: "read")
            lastUpdatedAt = .now
        } catch {
            guard isCurrent(generation) else { return }
            errors["read"] = error.localizedDescription
        }
    }

    /// The newest page in place of what it covers, followed by the older posts already loaded.
    static func merged(_ newest: [SourceActivity], into current: [SourceActivity]) -> [SourceActivity] {
        guard let oldest = newest.map(\.id).min() else { return current }
        return newest + current.filter { $0.id < oldest }
    }

    /// Reads each loaded account's equity curve; an account with no running owner has none.
    func refreshHistories(
        window: EquityHistoryWindow? = nil, using actions: (any AccountOperations)?
    ) async {
        guard let actions, let generation = privateAccessGeneration else { return }
        let window = window ?? historyWindow
        if window != historyWindow {
            historyWindow = window
            histories = [:]
        }
        for account in accounts where account.activeConfiguration {
            do {
                let history = try await actions.equityHistory(accountID: account.accountID, window: window)
                guard isCurrent(generation), historyWindow == window else { return }
                histories[account.accountID] = history
                errors.removeValue(forKey: "history:\(account.accountID)")
            } catch {
                guard isCurrent(generation) else { return }
                histories[account.accountID] = nil
                errors["history:\(account.accountID)"] = error.localizedDescription
            }
        }
    }

    func loadMoreAccounts(using actions: (any AccountOperations)?) async {
        guard
            let actions, let generation = privateAccessGeneration,
            let cursor = nextAccountCursor, !isLoadingMoreAccounts
        else { return }
        isLoadingMoreAccounts = true
        defer {
            if isCurrent(generation) { isLoadingMoreAccounts = false }
        }
        do {
            let page = try await actions.accounts(
                beforeAccountID: cursor, limit: accountPageSize
            )
            guard isCurrent(generation) else { return }
            accounts.append(contentsOf: page.items)
            nextAccountCursor = page.nextBeforeAccountID
            loadedAccountPageCount += 1
            recordUnavailable(page.unavailableAccounts)
            errors.removeValue(forKey: "read")
        } catch {
            guard isCurrent(generation) else { return }
            errors["read"] = error.localizedDescription
        }
    }

    func loadMore(using actions: (any AccountOperations)?) async {
        guard let actions, let generation = privateAccessGeneration,
            let cursor = nextActivityCursor
        else { return }
        do {
            let page = try await actions.sourceActivity(beforeSeq: cursor, limit: 25)
            guard isCurrent(generation) else { return }
            activity.append(contentsOf: page.items)
            nextActivityCursor = page.nextBeforeSeq
            recordUnavailable(page.unavailableAccounts)
            errors.removeValue(forKey: "read")
        } catch {
            guard isCurrent(generation) else { return }
            errors["read"] = error.localizedDescription
        }
    }

    func control(
        accountID: String, action: AccountControlAction,
        preference: RecoveryPreference? = nil, using actions: (any AccountOperations)?
    ) async {
        guard let actions, let generation = privateAccessGeneration,
            !pendingAccounts.contains(accountID)
        else { return }
        let command: AccountControlCommand
        if let previous = retryCommands[accountID],
            previous.action == action, previous.recoveryPreference == preference
        {
            command = previous
        } else {
            command = AccountControlCommand(
                commandID: UUID().uuidString.lowercased(), accountID: accountID,
                action: action, recoveryPreference: preference
            )
        }
        retryCommands[accountID] = command
        pendingAccounts.insert(accountID)
        defer {
            if isCurrent(generation) { pendingAccounts.remove(accountID) }
        }
        do {
            _ = try await actions.controlAccount(command)
            guard isCurrent(generation) else { return }

            let pageCount = max(loadedAccountPageCount, 1)
            var refreshedAccounts: [AccountOverview] = []
            var cursor: String?
            var refreshedPageCount = 0
            var targetFound = false
            repeat {
                let page = try await actions.accounts(
                    beforeAccountID: cursor, limit: accountPageSize
                )
                guard isCurrent(generation) else { return }
                refreshedAccounts.append(contentsOf: page.items)
                targetFound = targetFound || page.items.contains { $0.accountID == accountID }
                cursor = page.nextBeforeAccountID
                refreshedPageCount += 1
                if cursor == nil || (refreshedPageCount >= pageCount && targetFound) {
                    break
                }
            } while true
            guard isCurrent(generation) else { return }
            accounts = refreshedAccounts
            nextAccountCursor = cursor
            loadedAccountPageCount = refreshedPageCount
            retryCommands.removeValue(forKey: accountID)
            errors.removeValue(forKey: accountID)
        } catch {
            guard isCurrent(generation) else { return }
            errors[accountID] = error.localizedDescription
        }
    }

    /// Settles a holdings question the owner answered, then rereads the accounts so the warning
    /// and the held-back entries clear together.
    func resolveOwnership(_ fix: OwnershipFix, using actions: (any AccountOperations)?) async {
        let accountID = fix.request.accountID
        guard let actions, privateAccessGeneration != nil, !pendingAccounts.contains(accountID) else { return }
        pendingAccounts.insert(accountID)
        defer { pendingAccounts.remove(accountID) }
        do {
            _ = try await actions.resolveOwnership(accountID: accountID, resolution: fix.request)
            errors.removeValue(forKey: accountID)
        } catch {
            errors[accountID] = L10n.string(
                "The holdings couldn't be settled: %@. Check the broker for open orders in %@, then try again.",
                error.localizedDescription, fix.request.symbol)
            return
        }
        await refresh(using: actions)
    }

    /// Accounts the saved setup copies into that couldn't be read. One left by an earlier setup
    /// isn't the owner's concern any more, so it isn't shown.
    func unavailable(in setup: TradingConfiguration?) -> [AccountUnavailable] {
        guard let setup else { return unavailableAccounts }
        let ids = Set(setup.accounts.map(\.id))
        return unavailableAccounts.filter { ids.contains($0.accountID) }
    }

    func loadFeed(accountID: String, more: Bool = false, using actions: (any AccountOperations)?) async {
        guard let actions, let generation = privateAccessGeneration else { return }
        let cursor = more ? feedCursors[accountID] : nil
        if more && cursor == nil { return }
        do {
            let page = try await actions.accountFeed(accountID: accountID, beforeSeq: cursor, limit: 25)
            guard isCurrent(generation) else { return }
            feeds[accountID] = more ? (feeds[accountID] ?? []) + page.items : page.items
            feedCursors[accountID] = page.nextBeforeSeq
            errors.removeValue(forKey: "feed:\(accountID)")
        } catch {
            guard isCurrent(generation) else { return }
            errors["feed:\(accountID)"] = error.localizedDescription
        }
    }

    /// The newest page of every listed account's feed; an account already paged further keeps
    /// its older rows until the owner reloads it.
    func refreshFeeds(using actions: (any AccountOperations)?) async {
        for account in accounts where (feeds[account.accountID]?.count ?? 0) <= 25 {
            await loadFeed(accountID: account.accountID, using: actions)
        }
    }

    /// Sales the owner made, from every account, newest first; Activity lists them with the posts.
    var ownerSales: [(accountID: String, item: AccountFeedItem)] {
        feeds.flatMap { accountID, items in
            items.filter { $0.source == "you" && $0.kind == "sold" }.map { (accountID, $0) }
        }
        .sorted { (Humanize.date($0.item.at) ?? .distantPast) > (Humanize.date($1.item.at) ?? .distantPast) }
    }

    /// Keep one entry per account; the latest page's reason replaces an earlier one.
    private func recordUnavailable(_ gaps: [AccountUnavailable]) {
        for gap in gaps {
            unavailableAccounts.removeAll { $0.accountID == gap.accountID }
            unavailableAccounts.append(gap)
        }
    }

    func clearPrivateEvidence() {
        privateAccessGeneration = nil
        accounts = []
        nextAccountCursor = nil
        loadedAccountPageCount = 0
        activity = []
        nextActivityCursor = nil
        unavailableAccounts = []
        feeds = [:]
        feedCursors = [:]
        pendingAccounts = []
        isRefreshing = false
        isLoadingMoreAccounts = false
        errors = [:]
        retryCommands = [:]
        lastUpdatedAt = nil
        histories = [:]
        historyWindow = .today
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        privateAccessGeneration == generation
    }
}
