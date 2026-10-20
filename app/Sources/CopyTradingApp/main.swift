import AppKit

// The app's own NSApplication must exist before SwiftUI asks for the shared one.
_ = CopyTradingApplication.shared
CopyTradingApp.main()
