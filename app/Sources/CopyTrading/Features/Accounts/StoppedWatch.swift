import DesktopCore

/// Which accounts stopped copying on their own between two reads of the trading status, so the app
/// can say each stop once. An account counts only if the app saw it running first: one that never
/// opened was reported when copying started, and a pause the owner asked for is not a stop. When
/// the whole run fails, every account that was running stopped with it.
struct StoppedWatch {
    private var running: Set<String> = []

    /// The accounts, by name, that were running at the last read and are not now because the engine
    /// stopped them. Each failure is returned once: an account has to run again to stop again.
    mutating func stopped(in status: TradingStatus?) -> [String] {
        guard let status else {
            running = []
            return []
        }
        let runFailed = status.state == .failed
        let stopped = status.accounts.filter {
            running.contains($0.id) && ($0.state == "failed" || (runFailed && $0.state != "running"))
        }
        running = Set(status.accounts.filter { $0.state == "running" }.map(\.id))
        return stopped.map(\.id).sorted()
    }
}
