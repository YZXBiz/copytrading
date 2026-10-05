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
        NavigationStack {
            Form {
                Section(L10n.string("Historical message")) {
                    Text(source.text).textSelection(.enabled)
                    LabeledContent(L10n.string("Received"), value: Humanize.timestamp(source.sourceAt))
                    LabeledContent(L10n.string("Capture"), value: Humanize.code(source.captureStatus))
                }

                Section(L10n.string("Guru and accounts")) {
                    if routes.isEmpty {
                        ContentUnavailableView(
                            L10n.string("No saved gurus"),
                            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                            description: Text(L10n.string("Save a guru and start copying before evaluating older posts."))
                        )
                    } else {
                        Picker(L10n.string("Saved guru"), selection: $selectedRouteID) {
                            ForEach(routes) { route in
                                Text(routeLabel(route)).tag(Optional(route.id))
                            }
                        }
                        .accessibilityIdentifier("activity.historicalEvaluation.route")
                        if let selectedRoute,
                            let profile = configuration?.profiles.first(where: {
                                $0.profileRevision == selectedRoute.profileRevision
                            })
                        {
                            LabeledContent(L10n.string("Guru"), value: profile.displayName)
                            LabeledContent(L10n.string("Guru version"), value: Humanize.revision(profile.profileRevision))
                            LabeledContent(L10n.string("Exit fractions apply to"), value: exitBasisTitle(profile.exitBasis))
                            ForEach(selectedRoute.connections) { connection in
                                LabeledContent(
                                    connection.accountID,
                                    value: L10n.string(
                                        "Full position %@: each call buys the guru's share of it",
                                        Humanize.usd(connection.fullPositionUSD))
                                )
                            }
                        }
                    }
                }

                Section {
                    Button(L10n.string("Evaluate Message"), systemImage: "wand.and.stars") {
                        guard let selectedRouteID else { return }
                        Task {
                            await feature.evaluate(
                                sourceID: source.sourceID,
                                routeID: selectedRouteID,
                                using: model
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(feature.isEvaluating || selectedRouteID == nil || !model.isTradingUnlocked)
                    .accessibilityIdentifier("activity.historicalEvaluation.run")
                    if feature.isEvaluating {
                        ProgressView(L10n.string("Evaluating with the configured model"))
                    }
                    if let error = feature.error {
                        Callout(error, tone: .critical)
                    }
                } footer: {
                    Text(L10n.string("Simulated with the configured model. No order is placed."))
                }

                if let evaluation = feature.evaluation {
                    evaluationSection(evaluation)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.string("Historical Evaluation"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done")) {
                        feature.clear()
                        dismiss()
                    }
                }
            }
            .task {
                if selectedRouteID == nil { selectedRouteID = routes.first?.id }
            }
            .onChange(of: model.isTradingUnlocked) { _, unlocked in
                if !unlocked { feature.clear() }
            }
        }
        .frame(minWidth: 580, idealWidth: 620, minHeight: 600, idealHeight: 720)
    }

    @ViewBuilder
    private func evaluationSection(_ evaluation: ProfileEvaluation) -> some View {
        Section(L10n.string("Simulated result · no orders")) {
            LabeledContent(L10n.string("Decision")) {
                StatusBadge(Humanize.code(evaluation.decision), tone: StatusTone(code: evaluation.decision))
            }
            LabeledContent(L10n.string("Provider"), value: "\(evaluation.provider) · \(evaluation.model)")
            LabeledContent(L10n.string("Guru"), value: evaluation.guruID)
            LabeledContent(L10n.string("Guru version"), value: Humanize.revision(evaluation.profileRevision))
            LabeledContent(L10n.string("Reason"), value: Humanize.code(evaluation.reason))
            Text(L10n.string(evaluation.costNotice)).foregroundStyle(.secondary)
                .accessibilityIdentifier("activity.historicalEvaluation.costNotice")
            ForEach(Array(evaluation.instructions.enumerated()), id: \.offset) { _, instruction in
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        L10n.string(
                            "%@ %@ at %@", L10n.string(Humanize.code(instruction.action.rawValue)), instruction.symbol,
                            Humanize.usd(instruction.price))
                    )
                    .font(.headline)
                    Text(
                        L10n.string(
                            "Evidence: %@ · %@ · %@", instruction.actionEvidence, instruction.symbolEvidence, instruction.priceEvidence)
                    )
                    .foregroundStyle(.secondary)
                    if let fraction = instruction.fraction {
                        Text(L10n.string("Source fraction: %@ · evidence %@", fraction, instruction.fractionEvidence ?? "unavailable"))
                    }
                    if let basis = instruction.exitBasis {
                        Text(L10n.string("Exit fractions apply to %@", exitBasisTitle(basis)))
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(Array(evaluation.destinations.enumerated()), id: \.offset) { _, destination in
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        L10n.string(
                            "%@ · %@ %@", destination.accountID, L10n.string(Humanize.code(destination.action.rawValue)), destination.symbol
                        )
                    )
                    .font(.headline)
                    if let budget = destination.budgetUSD {
                        Text(
                            L10n.string(
                                "Estimated budget %@ · quantity %@", Humanize.usd(budget), destination.estimatedQuantity ?? "unavailable"))
                    }
                    if let basis = destination.exitBasis {
                        Text(L10n.string("Exit fractions apply to %@", exitBasisTitle(basis)))
                    }
                    Text(L10n.string(Humanize.code(destination.reason)))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(evaluation.reviewReasons, id: \.self) { reason in
                Callout(L10n.string(Humanize.code(reason)), tone: .caution)
            }
            Callout(L10n.string("Simulated only. This preview cannot enqueue or submit an order."))
                .accessibilityIdentifier("activity.historicalEvaluation.noOrder")
        }
    }

    @MainActor private func routeLabel(_ route: TradingRouteConfiguration) -> String {
        let profileName =
            configuration?.profiles.first(where: {
                $0.profileRevision == route.profileRevision
            })?.displayName ?? route.guruID
        let author = route.authorID.map { L10n.string("author %@", $0) } ?? L10n.string("any author")
        return L10n.string("%@ · channel %@ · %@", profileName, route.channelID, author)
    }

    @MainActor private func exitBasisTitle(_ basis: TradingExitBasis) -> String {
        switch basis {
        case .originalPosition: L10n.string("original position")
        case .remainingPosition: L10n.string("remaining position")
        }
    }
}
