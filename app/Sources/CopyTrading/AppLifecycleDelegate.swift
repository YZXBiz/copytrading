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
