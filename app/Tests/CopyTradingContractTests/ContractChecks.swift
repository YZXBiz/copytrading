import Testing

/// The app's native contract checks, one at a time in this order and on the main actor, as the
/// executable ran them. `swift test --filter` picks one by name.
enum ContractCheck: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case activitySourceReading = "activity source reading"
    case activityDestinationOutcomes = "activity destination outcomes"
    case activityCard = "activity card"
    case activityTimeline = "activity timeline"
    case liveSteps = "live steps"
    case appWindowLifecycle = "app window lifecycle"
    case quitRequest = "quit with a sheet open"
    case connectionsDraft = "connections draft"
    case guidedSetup = "guided setup"
    case setupImport = "setup import"
    case equityChartScale = "equity chart scale"
    case connectionsAndSettingsPages = "connections and settings pages"
    case providerChoice = "provider choice"
    case lotSaleFlow = "lot sale flow"
    case assistantModel = "assistant model"
    case assistantProposals = "assistant proposals"
    case agentSetupFlow = "agent setup from the command line"
    case assistantHelp = "assistant help"
    case assistantPanel = "assistant panel"
    case settingsSaveFlow = "settings save and start flow"
    case orderApproval = "order approval"
    case keepAwake = "keep the Mac awake while copying"
    case backupRestoreNotes = "backup and restore notes"
    case updateOffer = "update offer banner"
    case copyingStopped = "copying stopped notice"
    case guruFeed = "guru feed"
    case manualInstructionGuess = "manual instruction guess"
    case fillWatch = "fill notifications"
    case positionStory = "position story"
    case liveQuote = "live quote"
    case setupCheckProblems = "setup check problems"
    case copySheet = "copy sheet amount and price"
    case paletteContrast = "palette contrast"
    case controlsPass = "controls pass"

    var testDescription: String { rawValue }

    @MainActor func run() async throws {
        switch self {
        case .activitySourceReading: try checkActivitySourceReadingRepresentation()
        case .activityDestinationOutcomes: try checkActivityDestinationInstructionOutcomes()
        case .activityCard: try runActivityCardTests()
        case .activityTimeline: try runActivityTimelineTests()
        case .liveSteps: try runLiveStepTests()
        case .appWindowLifecycle: try await runAppWindowLifecycleTests()
        case .quitRequest: try runQuitRequestTests()
        case .connectionsDraft: try runConnectionsDraftTests()
        case .guidedSetup: try runGuidedSetupTests()
        case .setupImport: try runSetupImportTests()
        case .equityChartScale: try runEquityChartScaleTests()
        case .connectionsAndSettingsPages: try runConnectionsAndSettingsPagesTests()
        case .providerChoice: try runProviderChoiceTests()
        case .lotSaleFlow: try await runLotSaleFlowTests()
        case .assistantModel: try await runAssistantModelTests()
        case .assistantProposals: try await runAssistantProposalTests()
        case .agentSetupFlow: try await runAgentSetupFlowTests()
        case .assistantHelp: try runAssistantHelpTests()
        case .assistantPanel: try runAssistantPanelTests()
        case .settingsSaveFlow: try await TradingSettingsSaveTests.runSettingsSaveFlow()
        case .orderApproval: try await runOrderApprovalTests()
        case .keepAwake: try runKeepAwakeTests()
        case .backupRestoreNotes: try await runBackupRestoreNoteTests()
        case .updateOffer: try runUpdateOfferTests()
        case .copyingStopped: try runCopyingStoppedTests()
        case .guruFeed: try await runGuruFeedTests()
        case .manualInstructionGuess: try runManualInstructionGuessTests()
        case .fillWatch: try runFillWatchTests()
        case .positionStory: try await runPositionStoryTests()
        case .liveQuote: try runLiveQuoteTests()
        case .setupCheckProblems: try runSetupCheckProblemTests()
        case .copySheet: try runCopySheetTests()
        case .paletteContrast: try runPaletteContrastTests()
        case .controlsPass: try await runControlsPassTests()
        }
    }
}

@Test(.serialized, arguments: ContractCheck.allCases)
@MainActor func contracts(_ check: ContractCheck) async throws {
    try await check.run()
}
