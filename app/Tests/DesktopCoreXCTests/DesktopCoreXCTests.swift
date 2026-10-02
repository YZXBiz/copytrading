#if canImport(XCTest)
    import DesktopCore
    import Foundation
    import XCTest

    final class DesktopCoreXCTests: XCTestCase {
        func testCompletedWorkflowContract() throws {
            let packageRoot = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let data = try Data(contentsOf: packageRoot.appending(path: "Resources/Contracts/completed-self-test.json"))
            let response = try JSONDecoder().decode(EngineResponse.self, from: data)
            guard case .workflow(let workflow) = try response.successValue() else {
                return XCTFail("Expected a completed workflow result")
            }
            XCTAssertEqual(workflow.commandID, "sim-1")
            XCTAssertEqual(workflow.outcomes.count, 2)
            XCTAssertTrue(workflow.outcomes.allSatisfy { $0.result == .simulated })
        }

        func testExplicitStopSuppressesAutomaticWindowStart() {
            var intent = AppStartupIntent()
            XCTAssertTrue(intent.allowsAutomaticStart)
            intent.stop()
            XCTAssertFalse(intent.allowsAutomaticStart)
            intent.startRequested()
            XCTAssertTrue(intent.allowsAutomaticStart)
        }

        func testRestartBudgetAndStopTransition() {
            XCTAssertEqual(RestartTransitionPolicy.nextAttempt(attemptsUsed: 0, maximumRestarts: 2, explicitlyStopped: false), 1)
            XCTAssertEqual(RestartTransitionPolicy.nextAttempt(attemptsUsed: 1, maximumRestarts: 2, explicitlyStopped: false), 2)
            XCTAssertNil(RestartTransitionPolicy.nextAttempt(attemptsUsed: 2, maximumRestarts: 2, explicitlyStopped: false))
            XCTAssertNil(RestartTransitionPolicy.nextAttempt(attemptsUsed: 0, maximumRestarts: 2, explicitlyStopped: true))
        }
    }
#endif
