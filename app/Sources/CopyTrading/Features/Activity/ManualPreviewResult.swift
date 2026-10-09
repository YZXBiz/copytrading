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
        }
        .padding(.vertical, 6)
    }

    @MainActor private var headline: String {
        guard let plan = preview?.plan else {
            return L10n.string("%@ · trade %lld", request.accountID, Int64(request.instructionIndex + 1))
        }
        let quantity = Decimal(engine: plan.quantity).map(Humanize.shareCount) ?? plan.quantity
        let limit = Decimal(engine: plan.limitPrice).map(Humanize.usd)
        let side = L10n.string(plan.side.lowercased() == "sell" ? "Sell" : "Buy")
        return limit.map { L10n.string("%@ %@ %@ at %@ in %@", side, quantity, plan.symbol, $0, request.accountID) }
            ?? L10n.string("%@ %@ %@ in %@", side, quantity, plan.symbol, request.accountID)
    }

    @MainActor private var detail: String? {
        guard let preview, preview.plan != nil else { return nil }
        let quote = Decimal(engine: preview.freshPrice).map { L10n.string("Last price %@", Humanize.usd($0)) }
        let age = Duration.seconds(preview.sourceAgeSeconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
        return [quote, L10n.string("posted %@ ago", age)].compactMap { $0 }.joined(separator: " · ")
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
            problems += preview.reasons.map { Reason.text($0) }
            problems += preview.checks.filter { $0.status == "blocked" && $0.reason.map { !preview.reasons.contains($0) } ?? true }
                .map { Reason.text($0.reason ?? $0.name) }
        } else if let error = feature.errors[request.previewID] {
            problems.append(L10n.string(error))
        }
        if let confirmation {
            if let error = feature.errors[confirmation.commandID] { problems.append(L10n.string(error)) }
            if let error = feature.commandOutcomes[confirmation.commandID]?.error { problems.append(L10n.string(error)) }
        }
        return problems
    }
}
