import DesktopCore
import SwiftUI

/// What the engine says one drafted trade would place in one account, read fresh from the market
/// and the account: the order, or why it can't go, then what became of it once sent.
struct ManualPreviewResult: View {
    let request: ManualPreviewRequest
    let confirmation: ManualConfirmationRequest?
    let feature: ManualReviewFeatureModel

    private var preview: ManualOrderPreview? { feature.previews[request.previewID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(headline)
                    .font(DesignTokens.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                Spacer(minLength: 8)
                if let status { StatusBadge(status.text, tone: status.tone) }
            }
            if let detail {
                Text(detail)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
            }
            ForEach(problems, id: \.self) { problem in
                Callout(problem, tone: .critical)
            }
            ForEach(warnings, id: \.self) { warning in
                Callout(warning, tone: .caution)
            }
        }
        .padding(.vertical, 6)
    }

    /// The order the engine planned, in the words the owner confirms: a buy by the dollars it
    /// spends after the max per order, a sell by its shares.
    @MainActor private var headline: String {
        guard let plan = preview?.plan else {
            return L10n.string("%@ · trade %lld", request.accountID, Int64(request.instructionIndex + 1))
        }
        if let budget = Decimal(engine: plan.budgetUSD) {
            return L10n.string("Buy %@ of %@ in %@", Humanize.dollars("\(budget)"), plan.symbol, request.accountID)
        }
        let quantity = Decimal(engine: plan.quantity).map { Humanize.shareCount($0) } ?? plan.quantity
        let limit = Decimal(engine: plan.limitPrice).map(Humanize.usd)
        let side = L10n.string(plan.side.lowercased() == "sell" ? "Sell" : "Buy")
        return limit.map { L10n.string("%@ %@ %@ at %@ in %@", side, quantity, plan.symbol, $0, request.accountID) }
            ?? L10n.string("%@ %@ %@ in %@", side, quantity, plan.symbol, request.accountID)
    }

    /// A buy's shares at its limit, then the fresh price and the post's age, shown whether or not
    /// the order can go.
    @MainActor private var detail: String? {
        guard let preview else { return nil }
        var parts: [String] = []
        if let plan = preview.plan, plan.budgetUSD != nil, let quantity = Decimal(engine: plan.quantity),
            let limit = Decimal(engine: plan.limitPrice)
        {
            parts.append(L10n.string("%@ at %@ or less", Humanize.shares(quantity), Humanize.usd(limit)))
        }
        // A buy is checked against the ask and a sell against the bid.
        let side = preview.instruction.action == .buy ? "Ask %@" : "Bid %@"
        if let fresh = Decimal(engine: preview.freshPrice) { parts.append(L10n.string(side, Humanize.usd(fresh))) }
        let age = Duration.seconds(preview.sourceAgeSeconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
                .locale(AppTime.locale))
        parts.append(L10n.string("posted %@ ago", age))
        return parts.joined(separator: " · ")
    }

    @MainActor private var status: (text: String, tone: StatusTone)? {
        if let confirmation, let outcome = feature.commandOutcomes[confirmation.commandID] {
            let code = outcome.result?.status ?? (outcome.error == nil ? "pending" : "failed")
            return (Humanize.code(code), StatusTone(code: code))
        }
        guard let preview else { return feature.errors[request.previewID] == nil ? (L10n.string("Checking"), .neutral) : nil }
        if preview.plan != nil, preview.reasons.isEmpty { return (L10n.string("Ready"), .positive) }
        return (L10n.string("Can't send"), .critical)
    }

    @MainActor private var problems: [String] {
        var problems: [String] = []
        if let preview {
            problems += preview.reasons.map { ManualRefusalText.reason($0) }
            problems += preview.checks.filter { $0.status == "blocked" && $0.reason.map { !preview.reasons.contains($0) } ?? true }
                .map { ManualRefusalText.reason($0.reason ?? $0.name) }
        } else if let error = feature.errors[request.previewID] {
            problems.append(ManualRefusalText.line(error))
        }
        if let confirmation {
            if let error = feature.errors[confirmation.commandID] { problems.append(ManualRefusalText.line(error)) }
            if let outcome = feature.commandOutcomes[confirmation.commandID] {
                if let error = outcome.error { problems.append(ManualRefusalText.line(error)) }
                // A refused or turned-down order says why, so "Rejected" is never the whole answer.
                if let result = outcome.result, let line = ManualRefusalText.outcome(of: result) {
                    problems.append(line)
                }
            }
        }
        return problems.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// What the owner should know before sending, without stopping them: an ask above the buy's
    /// limit, with the numbers, since the quote feed can sit far from the market.
    @MainActor private var warnings: [String] {
        guard let preview else { return [] }
        return preview.checks.filter { $0.status == "warning" && $0.reason == "quote_above_limit" }
            .map { _ in aboveLimit(preview) }
    }

    /// The ask, the bid, the limit and what it is made of, and what happens if it doesn't fill.
    @MainActor private func aboveLimit(_ preview: ManualOrderPreview) -> String {
        guard let ask = Decimal(engine: preview.freshPrice), let limit = Decimal(engine: preview.limitPrice),
            let price = Decimal(engine: preview.instruction.price), price > 0
        else { return Reason.text("quote_above_limit") }
        let allowance = ((limit / price - 1) as NSDecimalNumber).doubleValue
            .formatted(.percent.precision(.fractionLength(0...2)))
        let quote =
            Decimal(engine: preview.quote?.bid).map {
                L10n.string("The ask is %@ (bid %@)", Humanize.usd(ask), Humanize.usd($0))
            } ?? L10n.string("The ask is %@", Humanize.usd(ask))
        return L10n.string(
            "%@, above your limit of %@: %@ plus your %@. It may not fill, and is cancelled if it hasn't in time.",
            quote, Humanize.usd(limit), Humanize.usd(price), allowance)
    }
}
