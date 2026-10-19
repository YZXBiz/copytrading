import AppKit

@MainActor
public final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel? {
        didSet { observeWakeIfNeeded() }
    }
    private var isTerminating = false
    private var wakeObserver: NSObjectProtocol?

    private func observeWakeIfNeeded() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model?.runtimeDidWake()
            }
        }
    }

    private func stopObservingWake() {
        guard let wakeObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        self.wakeObserver = nil
    }

    override public init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.saved.apply()
        // `open -j`, a login item set to Hide, and Resume at login all start the app hidden. The
        // window exists but stays off screen, and copying cannot start until someone unlocks it.
        NSApp.unhide(nil)
    }

    /// `open`, a Dock click, and AppleScript `reopen` land here. A hidden app does not unhide for a
    /// reopen on its own, so the window stayed away until something else activated the app.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        sender.unhide(nil)
        return true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopObservingWake()
        guard let model else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task {
            await model.stopRuntime()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
