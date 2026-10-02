#if DEBUG
    import DesktopCore
    import Foundation

    /// Debug builds only: lets `app/scripts/ui_journeys.py` skip owner authentication.
    /// Release bundles compile this out, and `verify_bundle.py` rejects a binary that contains it.
    enum UITestLaunch {
        static let unlockVariable = "COPYTRADING_UI_TEST_UNLOCK"

        /// Journeys read the real window; a tip floating over it would hide what they check.
        static var hidesTips: Bool {
            ProcessInfo.processInfo.environment[unlockVariable] == "1"
        }

        /// Honored only with an explicit switch and a state root under a temporary directory,
        /// so the bypass can never unlock the real installation or its Keychain items.
        /// A requested but unsafe setup stops the app instead of falling back to a password prompt.
        static func appUnlock(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppUnlock? {
            guard environment[unlockVariable] == "1" else { return nil }
            guard let stateRoot = environment["COPYTRADING_STATE_ROOT"], isTemporary(stateRoot) else {
                fatalError("\(unlockVariable) requires COPYTRADING_STATE_ROOT under a temporary directory")
            }
            return AppUnlock(authenticator: ApprovingAuthenticator())
        }

        /// macOS reports /private/tmp as /tmp once symlinks resolve, so compare both spellings.
        private static func isTemporary(_ path: String) -> Bool {
            let candidates = spellings(of: path)
            let roots = spellings(of: NSTemporaryDirectory()).union(["/tmp", "/private/tmp"])
            return candidates.contains { candidate in
                roots.contains { root in candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/") }
            }
        }

        private static func spellings(of path: String) -> Set<String> {
            let url = URL(filePath: path)
            return [url.standardizedFileURL.path, url.resolvingSymlinksInPath().path]
        }
    }

    private actor ApprovingAuthenticator: AppOwnerAuthenticator {
        func authenticate(localizedReason: String) async throws {}
        func invalidate() async {}
    }
#endif
