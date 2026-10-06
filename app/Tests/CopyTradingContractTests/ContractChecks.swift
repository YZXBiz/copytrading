import Testing

/// The app's native contract checks, one at a time in this order and on the main actor, as the
/// executable ran them. `swift test --filter` picks one by name.
enum ContractCheck: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case activitySourceReading = "activity source reading"
    case activityDestinationOutcomes = "activity destination outcomes"
    case activityCard = "activity card"
    case appWindowLifecycle = "app window lifecycle"
    case connectionsDraft = "connections draft"
    case guidedSetup = "guided setup"
    case equityChartScale = "equity chart scale"
    case connectionsAndSettingsPages = "connections and settings pages"
    case providerChoice = "provider choice"
    case lotSaleFlow = "lot sale flow"
    case assistantModel = "assistant model"
    case assistantProposals = "assistant proposals"
    case assistantHelp = "assistant help"
    case assistantPanel = "assistant panel"
    case settingsSaveFlow = "settings save and start flow"
    case orderApproval = "order approval"
    case keepAwake = "keep the Mac awake while copying"

    var testDescription: String { rawValue }

    @MainActor func run() async throws {
        switch self {
        case .activitySourceReading: try checkActivitySourceReadingRepresentation()
        case .activityDestinationOutcomes: try checkActivityDestinationInstructionOutcomes()
        case .activityCard: try runActivityCardTests()
        case .appWindowLifecycle: try await runAppWindowLifecycleTests()
        case .connectionsDraft: try runConnectionsDraftTests()
        case .guidedSetup: try runGuidedSetupTests()
        case .equityChartScale: try runEquityChartScaleTests()
        case .connectionsAndSettingsPages: try runConnectionsAndSettingsPagesTests()
        case .providerChoice: try runProviderChoiceTests()
        case .lotSaleFlow: try await runLotSaleFlowTests()
        case .assistantModel: try await runAssistantModelTests()
        case .assistantProposals: try await runAssistantProposalTests()
        case .assistantHelp: try runAssistantHelpTests()
        case .assistantPanel: try runAssistantPanelTests()
        case .settingsSaveFlow: try await TradingSettingsSaveTests.runSettingsSaveFlow()
        case .orderApproval: try await runOrderApprovalTests()
        case .keepAwake: try runKeepAwakeTests()
        }
    }
}

@Test(.serialized, arguments: ContractCheck.allCases)
@MainActor func contracts(_ check: ContractCheck) async throws {
    try await check.run()
}
