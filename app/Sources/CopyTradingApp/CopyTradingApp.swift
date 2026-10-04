import CopyTradingUI
import SwiftUI

@main
@MainActor
struct CopyTradingApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycle

    var body: some Scene {
        CopyTradingScene(lifecycle: lifecycle)
    }
}
