import DesktopCore
import Foundation
import Testing

/// Counts what the guard asks macOS for, instead of keeping the test machine awake.
@MainActor
private final class PowerLog {
    var begun: [String] = []
    var ended = 0

    func guarded() -> SleepGuard {
        SleepGuard(
            begin: { reason in
                self.begun.append(reason)
                return NSObject()
            },
            end: { _ in self.ended += 1 })
    }
}

@Test @MainActor func theGuardHoldsOnceAndLetsGoOnce() {
    let log = PowerLog()
    let sleepGuard = log.guarded()

    sleepGuard.hold(true)
    sleepGuard.hold(true)
    #expect(sleepGuard.isHolding)
    #expect(log.begun == [SleepGuard.reason], "asking twice must not stack two activities")

    sleepGuard.hold(false)
    sleepGuard.hold(false)
    #expect(!sleepGuard.isHolding)
    #expect(log.ended == 1, "letting go twice must end the activity once")
}

@Test func keepingTheMacAwakeIsOnByDefault() {
    #expect(LaunchPreferences().keepsMacAwake)
}
