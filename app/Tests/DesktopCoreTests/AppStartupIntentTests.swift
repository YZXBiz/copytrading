import DesktopCore

func runAppStartupIntentTests() throws {
    var intent = AppStartupIntent()
    try verify(intent.allowsAutomaticStart, "first window open should start the local runtime")
    intent.stop()
    try verify(!intent.allowsAutomaticStart, "reopening the window must preserve explicit Stop")
    intent.startRequested()
    try verify(intent.allowsAutomaticStart, "an explicit Start must clear the stopped intent")
}
