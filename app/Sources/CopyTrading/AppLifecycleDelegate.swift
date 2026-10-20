import AppKit

@MainActor
public final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel? {
        didSet { observeWakeIfNeeded() }
    }
    private var isTerminating = false
    private var isQuitting = false
    private var runtimeStopped = false
    private static weak var current: AppLifecycleDelegate?
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
        Self.current = self
    }

    /// Every way of quitting reaches `NSApplication.terminate(_:)`, which calls this instead of
    /// going on. It asks about setup edits the quit would drop and stops the engine; only then
    /// does it end any sheet and let `proceed` finish the quit, so the delegate never has to ask
    /// AppKit to wait for a delayed reply, which could not run the task that stops the engine.
    public static func requestQuit(proceed: @escaping @MainActor () -> Void) {
        guard let current else { return proceed() }
        current.requestQuit(proceed: proceed)
    }

    private func requestQuit(proceed: @escaping @MainActor () -> Void) {
        // AppKit asks again once `proceed` runs; a request while this one is under way is the same quit.
        if runtimeStopped {
            QuitRequest.endSheets(in: NSApp.windows)
            return proceed()
        }
        guard !isQuitting else { return }
        isQuitting = true
        guard
            QuitRequest.confirmed(
                hasUnsavedSetup: model?.hasUnsavedSetupChanges ?? false,
                confirmDiscardingSetup: Self.confirmQuitDiscardingSetup)
        else {
            isQuitting = false
            return
        }
        Task {
            await model?.stopRuntime()
            runtimeStopped = true
            QuitRequest.endSheets(in: NSApp.windows)
            // The engine has stopped, so nothing is left to wait for: should AppKit still be
            // quitting a few seconds on, finish the exit, since an update waits on it.
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) { exit(0) }
            proceed()
        }
    }

    private static func confirmQuitDiscardingSetup() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L10n.string("Quit and discard your setup changes?")
        alert.informativeText = L10n.string(
            "Edits and typed keys since your last saved setup are dropped. Your saved setup stays as it is.")
        alert.addButton(withTitle: L10n.string("Keep Editing"))
        alert.addButton(withTitle: L10n.string("Quit and Discard")).hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.saved.apply()
        // `open -j`, a login item set to Hide, and Resume at login all start the app hidden. The
        // window exists but stays off screen, and copying cannot start until someone unlocks it.
        NSApp.unhide(nil)
        // The Dock's Quit, an update's relaunch, and `tell application to quit` send an Apple Event
        // that AppKit answers without calling terminate(_:), so a sheet cancelled it unheard.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(quitRequested(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    }

    @objc private func quitRequested(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        // Quit goes on from a turn of the run loop of its own, so the Apple Event is answered now.
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { NSApp.terminate(nil) } }
    }

    /// `open`, a Dock click, and AppleScript `reopen` land here. A hidden app does not unhide for a
    /// reopen on its own, so the window stayed away until something else activated the app.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        sender.unhide(nil)
        return true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopObservingWake()
        if runtimeStopped { return .terminateNow }
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
