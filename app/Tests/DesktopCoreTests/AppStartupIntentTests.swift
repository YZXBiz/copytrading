import DesktopCore
import Testing

func runAppStartupIntentTests() throws {
    var intent = AppStartupIntent()
    try #require(intent.allowsAutomaticStart, "first window open should start the local runtime")
    intent.stop()
    try #require(!intent.allowsAutomaticStart, "reopening the window must preserve explicit Stop")
    intent.startRequested()
    try #require(intent.allowsAutomaticStart, "an explicit Start must clear the stopped intent")
}
