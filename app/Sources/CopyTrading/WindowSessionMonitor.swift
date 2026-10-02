import AppKit
import DesktopCore
import ObjectiveC
import SwiftUI

struct WindowSessionMonitor: NSViewRepresentable {
    let onOpen: @MainActor (UUID) -> Void
    let onClose: @MainActor (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen, onClose: onClose)
    }

    func makeNSView(context: Context) -> WindowObservationView {
        let view = WindowObservationView(frame: .zero)
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.attach(to: view.window)
        return view
    }

    func updateNSView(_ view: WindowObservationView, context: Context) {
        context.coordinator.update(onOpen: onOpen, onClose: onClose)
        context.coordinator.attach(to: view.window)
    }

    @MainActor
    final class Coordinator: NSObject {
        private final class SessionToken: NSObject {
            let id = UUID()
        }

        private static var tokenKey: UInt8 = 0

        private weak var window: NSWindow?
        private var sessionID: UUID?
        private let lifecycle = WindowSessionLifecycle()
        private var onOpen: @MainActor (UUID) -> Void
        private var onClose: @MainActor (UUID) -> Void

        init(
            onOpen: @escaping @MainActor (UUID) -> Void,
            onClose: @escaping @MainActor (UUID) -> Void
        ) {
            self.onOpen = onOpen
            self.onClose = onClose
        }

        func update(
            onOpen: @escaping @MainActor (UUID) -> Void,
            onClose: @escaping @MainActor (UUID) -> Void
        ) {
            self.onOpen = onOpen
            self.onClose = onClose
        }

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            detachFromCurrentWindow()

            let token: SessionToken
            if let existing = objc_getAssociatedObject(window, &Self.tokenKey) as? SessionToken {
                token = existing
            } else {
                token = SessionToken()
                objc_setAssociatedObject(window, &Self.tokenKey, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }

            self.window = window
            sessionID = token.id
            _ = lifecycle.attach(to: window, sessionID: token.id)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
            onOpen(token.id)
        }

        @objc private func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                window === self.window,
                let sessionID,
                let closedSessionID = lifecycle.close(window, sessionID: sessionID)
            else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: window
            )
            objc_setAssociatedObject(window, &Self.tokenKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            self.window = nil
            self.sessionID = nil
            onClose(closedSessionID)
        }

        private func detachFromCurrentWindow() {
            guard let window = self.window, let sessionID else { return }
            let closedSessionID = lifecycle.close(window, sessionID: sessionID)
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: window
            )
            objc_setAssociatedObject(window, &Self.tokenKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            self.window = nil
            self.sessionID = nil
            if let closedSessionID { onClose(closedSessionID) }
        }
    }
}

@MainActor
final class WindowObservationView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
