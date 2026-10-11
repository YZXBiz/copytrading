import SwiftUI

extension EnvironmentValues {
    /// The saved setup's reader model and order timeouts, for the live step of a post in flight.
    @Entry var postProgressContext = PostProgress.Context()
}
