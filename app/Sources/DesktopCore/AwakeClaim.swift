import Foundation
import IOKit.pwr_mgt

/// macOS's two keep-awake claims, held together. The idle-sleep claim works on battery too; the
/// system-sleep claim (what `caffeinate -s` holds) also keeps a closed MacBook awake while it is
/// plugged in, and macOS ignores it on battery.
@MainActor
public final class AwakeClaim: NSObject {
    private let activity: any NSObjectProtocol
    private var assertion: IOPMAssertionID = 0
    private let hasAssertion: Bool

    public init(reason: String) {
        activity = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled, reason: reason)
        hasAssertion =
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &assertion
            ) == kIOReturnSuccess
        super.init()
    }

    public func release() {
        ProcessInfo.processInfo.endActivity(activity)
        if hasAssertion { IOPMAssertionRelease(assertion) }
    }
}
