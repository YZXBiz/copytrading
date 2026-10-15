import DesktopCore
import Observation
import SwiftUI

@MainActor
@Observable
final class HistoricalProfileEvaluationModel {
    var evaluation: ProfileEvaluation?
    var error: String?
    var isEvaluating = false
    private var accessGeneration = 0

    func evaluate(sourceID: String, routeID: String, using model: AppModel) async {
        guard !isEvaluating else { return }
        isEvaluating = true
        evaluation = nil
        error = nil
        let requestGeneration = accessGeneration
        defer { isEvaluating = false }
        do {
            let result = try await model.evaluateHistoricalProfile(
                sourceID: sourceID, routeID: routeID
            )
            guard requestGeneration == accessGeneration, model.isTradingUnlocked else { return }
            evaluation = result
        } catch {
            guard requestGeneration == accessGeneration, model.isTradingUnlocked else { return }
            self.error =
                (error as? LocalizedError)?.errorDescription.map { L10n.string($0) }
                ?? L10n.string("Historical evaluation could not be completed.")
        }
    }

    func clear() {
        accessGeneration += 1
        evaluation = nil
        error = nil
    }
}

/// An earlier post read again with a saved guru's rules, as a simulation: the post, which guru's
/// rules to read it with, and what would have happened in each account. Nothing is ordered.
struct HistoricalProfileEvaluationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: SourceActivity
    @Bindable var model: AppModel
    @State private var feature = HistoricalProfileEvaluationModel()
    @State private var selectedRouteID: String?

    private var configuration: TradingConfiguration? { model.savedTradingConfiguration }
    private var routes: [TradingRouteConfiguration] { configuration?.routes ?? [] }
    private var selectedRoute: TradingRouteConfiguration? {
        routes.first(where: { $0.id == selectedRouteID })
    }

    var body: some View {
        SheetScaffold(
            kind: L10n.string("Historical Evaluation"),
            title: "“\(source.text)”",
            lede: byline
        ) {
            SheetSection(L10n.string("Guru and accounts")) {
                if routes.isEmpty {
                    Text(L10n.string("Save a guru and start copying before evaluating older posts."))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.vertical, 8)
                } else {
                    SheetRow(title: L10n.string("Saved guru")) {
                        SheetMenu(
                            label: L10n.string("Saved guru"),
                            choices: routes.map { (value: $0.id, title: SavedGuruLabel.text($0, in: configuration)) },
                            selection: Binding(
                                get: { selectedRouteID ?? routes.first?.id ?? "" }, set: { selectedRouteID = $0 })
                        )
                        .accessibilityIdentifier("activity.historicalEvaluation.route")
                    }
                    ForEach(selectedRoute?.connections ?? []) { connection in
                        SheetRow(
                            title: connection.accountID,
                            hint: L10n.string(
                                "Full position %@. A 1/6 call buys a sixth of it.", Humanize.usd(connection.fullPositionUSD))
                        ) {
                            EmptyView()
                        }
                    }
                }
            } footer: {
                Text(L10n.string("Simulated with the configured model. No order is placed."))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            if feature.isEvaluating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.string("Evaluating with the configured model"))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if let error = feature.error {
                Callout(error, tone: .critical)
            }
            if let evaluation = feature.evaluation {
                HistoricalEvaluationResult(evaluation: evaluation)
            }
        } actions: {
            Button(L10n.string("Done")) {
                feature.clear()
                dismiss()
            }
            .buttonStyle(SheetButtonStyle())
            .keyboardShortcut(.cancelAction)
            Button(L10n.string("Evaluate Message")) {
                guard let routeID = selectedRouteID else { return }
                Task { await feature.evaluate(sourceID: source.sourceID, routeID: routeID, using: model) }
            }
            .buttonStyle(SheetButtonStyle(isPrimary: true))
            .keyboardShortcut(.defaultAction)
            .disabled(feature.isEvaluating || selectedRouteID == nil || !model.isTradingUnlocked)
            .accessibilityIdentifier("activity.historicalEvaluation.run")
        }
        .frame(minWidth: 580, idealWidth: 620, minHeight: 520, idealHeight: 640)
        .task {
            if selectedRouteID == nil { selectedRouteID = routes.first?.id }
        }
        .onChange(of: model.isTradingUnlocked) { _, unlocked in
            if !unlocked { feature.clear() }
        }
    }

    /// Who posted it and when, as every post's byline reads.
    private var byline: String {
        let guru = GuruDirectory(configuration).gurus.first { $0.id == source.guruID }?.name
        let time = Humanize.timestamp(source.sourceAt)
        return guru.map { L10n.string("%@ · %@", $0, time) } ?? time
    }
}
