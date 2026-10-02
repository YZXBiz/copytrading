import AppKit
import DesktopCore
import Foundation

actor AppUpdateRuntimeLifecycle: UpdateRuntimeLifecycle {
    private let model: AppModel
    private var transition: MaintenanceTransition?

    init(model: AppModel) {
        self.model = model
    }

    func stopForUpdate() async throws {
        guard transition == nil else { throw UpdateInstallError.recoveryRequired }
        transition = try await model.beginUpdateMaintenance()
    }

    func startAfterUpdate() async throws {
        guard let transition else { throw UpdateInstallError.recoveryRequired }
        try await model.restartRuntimeAfterUpdateRollback(during: transition)
        await finish(transition)
    }

    func finishAfterRecoveryFailure() async {
        guard let transition else { return }
        await finish(transition)
    }

    func terminateCurrentApplication() async {
        if let transition { await finish(transition) }
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }

    private func finish(_ transition: MaintenanceTransition) async {
        guard self.transition == transition else { return }
        self.transition = nil
        await model.finishUpdateMaintenance(transition)
    }
}
