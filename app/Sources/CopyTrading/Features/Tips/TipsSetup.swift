import TipKit

/// Turns tips on once at launch: at most one an hour, each shown once, none during UI journeys.
enum TipsSetup {
    @MainActor
    static func configure() {
        #if DEBUG
            if UITestLaunch.hidesTips {
                Tips.hideAllTipsForTesting()
            }
        #endif
        // Configuring twice is the only failure, and tips are a convenience the app works without.
        try? Tips.configure([.displayFrequency(.hourly)])
    }
}
