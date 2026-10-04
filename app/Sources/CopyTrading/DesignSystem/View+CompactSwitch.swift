import SwiftUI

extension View {
    /// Every on/off switch in the app: the mini switch, so a row's words carry it, not the
    /// control. macOS 26 draws even a small switch large inside a grouped form.
    func compactSwitch() -> some View {
        toggleStyle(.switch).controlSize(.mini)
    }
}
