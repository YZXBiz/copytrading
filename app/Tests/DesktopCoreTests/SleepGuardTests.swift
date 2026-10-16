import DesktopCore
import Foundation
import IOKit.pwr_mgt
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

/// The real claim asks macOS for both kinds of awake, then gives both back; the system-sleep one
/// is what keeps a plugged-in Mac copying with the lid closed.
@Test @MainActor func theRealClaimHoldsSystemSleepAndGivesItBack() {
    func held() -> [String] {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
            let all = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
            let mine = all[NSNumber(value: getpid())]
        else { return [] }
        return mine.compactMap { $0[kIOPMAssertionTypeKey] as? String }
    }
    let claim = AwakeClaim(reason: "CopyTrading test claim")
    #expect(held().contains(kIOPMAssertionTypePreventSystemSleep))
    #expect(held().contains(kIOPMAssertionTypePreventUserIdleSystemSleep))
    claim.release()
    #expect(!held().contains(kIOPMAssertionTypePreventSystemSleep))
}
