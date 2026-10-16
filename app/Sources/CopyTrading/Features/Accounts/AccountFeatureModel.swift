import DesktopCore
import Foundation
import Observation

protocol AccountOperations: Sendable {
    func accounts(beforeAccountID: String?, limit: Int) async throws -> AccountOverviewPage
    func sourceActivity(beforeSeq: Int?, limit: Int) async throws -> SourceActivityPage
    func guruDayStats(dayStart: Date, dayEnd: Date) async throws -> GuruDayStatsPage
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
    private(set) var activity: [SourceActivity] = [] {
        didSet {
            let news = fillWatch.news(in: activity)
            if !news.isEmpty { onOrders?(news) }
        }
    }
    /// Every post the app knows of: the newest pages it loaded, and each call still waiting for
    /// the owner that the engine counted over the whole trading day, loaded or not. Its version
    /// of a post is the freshest, so it replaces a loaded one.
    var knownActivity: [SourceActivity] {
        let waiting = guruDays.values.flatMap(\.waiting)
        let held = Set(waiting.map(\.id))
        return (waiting + activity.filter { !held.contains($0.id) }).sorted { $0.id > $1.id }
    }
    private var fillWatch = FillWatch()
    /// Told of each copied order that newly went out or filled, once; the app turns them into
    /// notifications.
    var onOrders: ((FillWatch.News) -> Void)?
    /// Each guru's numbers for the owner's today, by guru, counted by the engine from every post
    /// of the day; `activity` holds only the newest pages.
    private(set) var guruDays: [String: GuruDayStats] = [:]
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
    /// The accounts whose curve for the current window was asked for, answered or not: a missing
    /// curve means "still reading" only until then.
    private(set) var historiesRead: Set<String> = []
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
            try await readGuruDays(using: actions, generation: generation)
            errors.removeValue(forKey: "read")
            lastUpdatedAt = .now
        } catch {
            guard isCurrent(generation) else { return }
            errors["read"] = Reason.refusal(error)
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
            try await readGuruDays(using: actions, generation: generation)
            errors.removeValue(forKey: "read")
            lastUpdatedAt = .now
        } catch {
            guard isCurrent(generation) else { return }
            errors["read"] = Reason.refusal(error)
        }
    }

    /// Each guru's numbers from the start of the owner's today to its end, in the zone chosen in
    /// Settings.
    private func readGuruDays(using actions: any AccountOperations, generation: UUID, now: Date = .now) async throws {
        let calendar = AppTime.calendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let page = try await actions.guruDayStats(dayStart: start, dayEnd: end)
        guard isCurrent(generation) else { return }
        guruDays = Dictionary(page.gurus.map { ($0.guruID, $0) }, uniquingKeysWith: { first, _ in first })
        recordUnavailable(page.unavailableAccounts)
    }

    /// The newest page in place of what it covers, followed by the older posts already loaded.
    static func merged(_ newest: [SourceActivity], into current: [SourceActivity]) -> [SourceActivity] {
        guard let oldest = newest.map(\.id).min() else { return current }
        return newest + current.filter { $0.id < oldest }
    }

    /// Reads the equity curve of each loaded account the broker can be asked about.
    func refreshHistories(
        window: EquityHistoryWindow? = nil, using actions: (any AccountOperations)?
    ) async {
        guard let actions, let generation = privateAccessGeneration else { return }
        let window = window ?? historyWindow
        if window != historyWindow {
            historyWindow = window
            histories = [:]
            historiesRead = []
        }
        for account in accounts where account.readsBrokerCurve {
            do {
                let history = try await actions.equityHistory(accountID: account.accountID, window: window)
                guard isCurrent(generation), historyWindow == window else { return }
                histories[account.accountID] = history
                historiesRead.insert(account.accountID)
                errors.removeValue(forKey: "history:\(account.accountID)")
            } catch {
                guard isCurrent(generation) else { return }
                histories[account.accountID] = nil
                historiesRead.insert(account.accountID)
                errors["history:\(account.accountID)"] = Reason.refusal(error)
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
            errors["read"] = Reason.refusal(error)
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
            errors["read"] = Reason.refusal(error)
        }
    }

    func control(
        accountID: String, action: AccountControlAction,
        preference: RecoveryPreference? = nil, using actions: (any AccountOperations)?
    ) async {
        guard let generation = privateAccessGeneration, !pendingAccounts.contains(accountID) else { return }
        guard let actions else {
            errors[accountID] = Self.noEngine
            return
        }
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
            errors[accountID] = Reason.refusal(error)
        }
    }

    /// The chart's range and day buttons. With no engine to read the curve from, the account says
    /// so instead of the buttons doing nothing.
    func chooseHistoryWindow(
        _ window: EquityHistoryWindow, for accountID: String, using actions: (any AccountOperations)?
    ) async {
        guard let actions else {
            errors[accountID] = L10n.string("The chart can't change while the engine is stopped. Start it in Settings → Engine.")
            return
        }
        await refreshHistories(window: window, using: actions)
    }

    /// What an account's button says when there is no engine to send its command to.
    static var noEngine: String {
        L10n.string("Nothing was sent: the engine isn't running. Start it in Settings → Engine, then try again.")
    }

    /// Settles a holdings question the owner answered, then rereads the accounts so the warning
    /// and the held-back entries clear together.
    func resolveOwnership(_ fix: OwnershipFix, using actions: (any AccountOperations)?) async {
        let accountID = fix.request.accountID
        guard privateAccessGeneration != nil, !pendingAccounts.contains(accountID) else { return }
        guard let actions else {
            errors[accountID] = Self.noEngine
            return
        }
        pendingAccounts.insert(accountID)
        defer { pendingAccounts.remove(accountID) }
        do {
            _ = try await actions.resolveOwnership(accountID: accountID, resolution: fix.request)
            errors.removeValue(forKey: accountID)
        } catch {
            errors[accountID] = L10n.string(
                "The holdings couldn't be settled: %@. Check the broker for open orders in %@, then try again.",
                Reason.refusal(error), fix.request.symbol)
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
            errors["feed:\(accountID)"] = Reason.refusal(error)
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
        guruDays = [:]
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
        historiesRead = []
        historyWindow = .today
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        privateAccessGeneration == generation
    }
}
