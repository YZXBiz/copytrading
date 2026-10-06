import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// The Mac is kept awake exactly while copying is on and the owner wants it (Settings → General).
@MainActor
func runKeepAwakeTests() throws {
    var held: [Bool] = []
    let sleepGuard = SleepGuard(
        begin: { _ in
            held.append(true)
            return NSObject()
        },
        end: { _ in held.append(false) })
    let model = AppModel(sleepGuard: sleepGuard)

    model.tradingStatus = try status(.paused)
    try #require(!sleepGuard.isHolding, "a paused setup kept the Mac awake")

    model.tradingStatus = try status(.starting)
    try #require(sleepGuard.isHolding, "starting to copy did not keep the Mac awake")
    model.tradingStatus = try status(.running)
    model.tradingStatus = try status(.degraded)
    try #require(held == [true], "staying in copying asked macOS again: \(held)")

    model.setKeepsMacAwake(false)
    try #require(!sleepGuard.isHolding, "turning the setting off left the Mac held awake")
    model.setKeepsMacAwake(true)
    try #require(sleepGuard.isHolding, "turning the setting back on while copying did not hold it")

    model.tradingStatus = try status(.pausing)
    try #require(!sleepGuard.isHolding, "pausing kept the Mac awake")
    model.tradingStatus = try status(.running)
    model.tradingStatus = nil
    try #require(!sleepGuard.isHolding, "a stopped engine kept the Mac awake")
    try #require(held == [true, false, true, false, true, false], "unexpected hold sequence \(held)")
}

private func status(_ state: TradingRunState) throws -> TradingStatus {
    try TradingStatusBuilder(state).connected().build()
}
