import SwiftUI

extension EnvironmentValues {
    @Entry var appUpdater: any AppUpdating = NoUpdates()
}
