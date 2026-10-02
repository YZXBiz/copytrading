import AppKit
import SwiftUI

/// Seats the window's close, minimize, and zoom buttons inside the workspace chrome.
///
/// A hidden title bar leaves them 8 points from the window's corner, which is exactly where the
/// inset sidebar panel's rounded edge begins, so the panel border cut through them. This moves
/// them into the panel, centered on its header row, and keeps them there when AppKit lays the
/// title bar out again (resizing, key changes, leaving full screen, changing displays).
struct WindowButtonPlacement: NSViewRepresentable {
    /// Distance from the window's leading edge to the close button.
    let leading: CGFloat
    /// Distance from the window's top edge to the buttons' vertical center.
    let centerY: CGFloat

    func makeNSView(context: Context) -> PlacementView { PlacementView() }

    func updateNSView(_ view: PlacementView, context: Context) {
        view.leading = leading
        view.centerY = centerY
        view.apply()
    }

    final class PlacementView: NSView {
        var leading: CGFloat = 20
        var centerY: CGFloat = 28
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didChangeScreenNotification,
                // Fires after every pass AppKit makes over the window, including the title bar
                // layout that follows a sidebar animation. Placement is a no-op when the buttons
                // are already seated, so checking each time is cheap and cannot loop.
                NSWindow.didUpdateNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                }
            }
            // AppKit also lays the title bar out on its own schedule. When it resets the buttons
            // or their container, that shows up as a frame change, so seat them again at once.
            let moved: [NSView?] = [
                window.standardWindowButton(.closeButton),
                window.standardWindowButton(.miniaturizeButton),
                window.standardWindowButton(.zoomButton),
                window.standardWindowButton(.closeButton)?.superview?.superview,
            ]
            for view in moved.compactMap({ $0 }) {
                view.postsFrameChangedNotifications = true
                observers.append(
                    NotificationCenter.default.addObserver(
                        forName: NSView.frameDidChangeNotification, object: view, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.apply() }
                    })
            }
            apply()
        }

        private var isApplying = false
        private var pitch: CGFloat?

        func apply() {
            // Moving the buttons posts frame changes that land back here; those are ignored, and
            // the passes below settle anything AppKit re-laid out in response.
            guard !isApplying else { return }
            isApplying = true
            defer { isApplying = false }
            for _ in 0..<3 {
                if place() { break }
            }
        }

        /// Seats the buttons; true when they were already seated.
        private func place() -> Bool {
            guard let window, !window.styleMask.contains(.fullScreen),
                let close = window.standardWindowButton(.closeButton),
                let minimize = window.standardWindowButton(.miniaturizeButton),
                let zoom = window.standardWindowButton(.zoomButton),
                let container = close.superview?.superview
            else { return true }
            var seated = true
            // The pitch is measured once, from AppKit's own layout; measuring it again after a
            // half-finished reset would shrink it, and the buttons would pile up.
            let measured = minimize.frame.minX - close.frame.minX
            if pitch == nil, measured >= close.frame.width + 4 { pitch = measured }
            let spacing = pitch ?? close.frame.width + 7
            // The title bar container must be tall enough to hold the buttons, or they clip.
            let height = centerY * 2
            var frame = container.frame
            frame.size.height = height
            frame.origin.y = window.frame.height - height
            if container.frame != frame {
                container.frame = frame
                seated = false
            }
            for (index, button) in [close, minimize, zoom].enumerated() {
                let origin = NSPoint(x: leading + CGFloat(index) * spacing, y: (height - button.frame.height) / 2)
                if button.frame.origin != origin {
                    button.setFrameOrigin(origin)
                    seated = false
                }
            }
            return seated
        }
    }
}
