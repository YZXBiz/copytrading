import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// A found update is offered in the window; Later puts that version off until the next launch, and
/// an update while copying says what happens to copying.
@MainActor
func runUpdateOfferTests() throws {
    let offer = UpdateOffer()
    try #require(offer.version == nil, "an offer appeared before any update was found")
    offer.found("0.1.0-alpha.9")
    try #require(offer.version == "0.1.0-alpha.9", "a found update was not offered")
    offer.postpone()
    try #require(offer.version == nil, "Later did not hide the offer")
    offer.found("0.1.0-alpha.9")
    try #require(offer.version == nil, "a postponed version came back before the next launch")
    offer.found("0.1.0-alpha.10")
    try #require(offer.version == "0.1.0-alpha.10", "a newer version after Later was not offered")
    offer.withdraw()
    try #require(offer.version == nil, "the banner stayed while Sparkle's window showed the update")

    let model = AppModel()
    model.tradingStatus = try TradingStatusBuilder(.paused).connected().build()
    try #require(model.updateCopyingNote == nil, "a paused setup was told copying would stop")
    model.tradingStatus = try TradingStatusBuilder(.running).connected().build()
    try #require(model.updateCopyingNote != nil, "copying was not told what the install does to it")

    let key = AppModel.resumesAfterUpdateKey
    UserDefaults.standard.removeObject(forKey: key)
    model.rememberCopyingForRelaunch()
    try #require(UserDefaults.standard.bool(forKey: key), "copying was not remembered for the relaunch")
    try #require(model.wantsCopyingOnLaunch, "the relaunch would not start copying again")
    UserDefaults.standard.removeObject(forKey: key)
}
