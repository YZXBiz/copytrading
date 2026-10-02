import SwiftUI

extension EnvironmentValues {
    /// The current tip generation; Help ▸ Show Tips Again bumps it so every tip can show again.
    @Entry var tipGeneration = 0
}
