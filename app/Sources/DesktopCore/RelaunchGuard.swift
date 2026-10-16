import Darwin
import Foundation

/// Sparkle quits the app to install an update, then reopens it. When its installer fails or hangs
/// after the app has quit, Sparkle never reopens the old version, and copying stays off until
/// someone notices. The guard is a small shell process that outlives the app. It waits for the
/// app to quit, gives the installer `patience` seconds to reopen it, and otherwise stops the
/// installer and opens whatever is now at the bundle path: the update if it landed, or the
/// version that was running.
public enum RelaunchGuard {
    /// Sparkle reopens the app within a few seconds of it quitting; two minutes is past any
    /// install that is still working.
    public static let patience = 120
    /// How long the app may take to quit (it stops the engine first) before the guard gives up:
    /// the install was put off.
    static let quitLimit = 300

    /// Arguments: the app's pid, its executable, its bundle, patience, and the opener.
    static let script = """
        app_pid=$1 executable=$2 bundle=$3 patience=$4 opener=$5
        is_running() { /bin/ps -axo comm= | /usr/bin/grep -qxF "$executable"; }
        waited=0
        while /bin/kill -0 "$app_pid" 2>/dev/null; do
            [ "$waited" -ge \(quitLimit) ] && exit 0
            /bin/sleep 1; waited=$((waited + 1))
        done
        waited=0
        while [ "$waited" -lt "$patience" ]; do
            is_running && exit 0
            /bin/sleep 1; waited=$((waited + 1))
        done
        is_running && exit 0
        for helper in $(/bin/ps -axo pid=,comm= | /usr/bin/awk -v prefix="$bundle/Contents/Frameworks/" 'index($0, prefix) { print $1 }'); do
            /bin/kill "$helper" 2>/dev/null
        done
        exec "$opener" "$bundle"
        """

    /// Starts the guard in a session of its own, so it outlives the app, with none of the app's
    /// open files: an inherited lock would keep the reopened app from starting. Returns its pid.
    @discardableResult
    public static func start(
        appPID: pid_t, executable: URL, bundle: URL, patience: Int = patience,
        opener: URL = URL(fileURLWithPath: "/usr/bin/open")
    ) throws -> pid_t {
        let arguments = [
            "/bin/sh", "-c", script, "copytrading-relaunch-guard", String(appPID), executable.path,
            bundle.path, String(patience), opener.path,
        ]
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        let argv = arguments.map { strdup($0) } + [nil]
        let environment = [strdup("PATH=/usr/bin:/bin"), nil]
        defer { (argv + environment).forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, "/bin/sh", &actions, &attributes, argv, environment)
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EINVAL) }
        return pid
    }
}
