# Local operations

This page covers the app repository's developer workflow. It does not describe a running server deployment.

| Command | Purpose |
| --- | --- |
| `make doctor` | Check that this Mac can build and run the app, and print the fix for anything missing. |
| `make app` | Run `doctor`, prepare the pinned runtime, build the app, and open it. |
| `make dev` | Install the engine's virtual environment (`engine/.venv`) for your editor. |
| `make check` | Run the engine and app-script tests, Ruff, and Ty. |
| `make check-linux` | Run the engine tests on Linux in Docker, with the repository mounted read-only. |
| `make coverage` | Run the engine tests with line and branch coverage. It fails under 80% and writes an HTML report to `dist/coverage/`. |
| `make check-mutations` | Run selected execution-policy mutation probes on disposable copies. |
| `make desktop-build` | Assemble the local macOS app from the prepared runtime, signed with your Apple Development identity when the login keychain has one (ad hoc otherwise). |
| `make desktop-check` | Run code checks, Swift formatting, the build, and bundle verification. |
| `make desktop-smoke` | Launch a disposable copy of the built bundle for a local smoke test. |
| `make lint-swift` | Check Swift formatting; `make format-swift` fixes it. |
| `make ui-journeys` | Build a debug copy and drive the real window through the journeys in [acceptance](acceptance.md), saving screenshots in `dist/ui-test/screenshots/`. Needs [Peekaboo](https://github.com/steipete/Peekaboo). |
| `make release RELEASE_VERSION=…` | Build and verify the developer-preview assets for a clean commit ([releases](releases.md)). |

`make app` prepares the pinned native runtime when it is missing or its manifest changed. Override `APP` and `RUNTIME` to build somewhere other than `dist/`; building over `dist/CopyTrading.app` replaces that bundle. Generated bundles, virtual environments, and operational state are ignored by Git. App state belongs under the user's Application Support directory. Do not use repository cleanup commands to remove app state or credentials.

When running the bundled Python directly for a developer probe, pass `-B` or set `PYTHONDONTWRITEBYTECODE=1` before starting it. The normal app already disables bytecode writes. Generated cache files inside the bundle cause its integrity check to reject it; rebuild the artifact if a probe modifies it.

The app owns its local Python engine process. Stop it through the app's controls. A startup failure or uncertain command should be resolved from the app's persisted status and SQLite evidence before trying another command identity. A healthy process alone does not establish readiness to trade.

Diagnostics are a private journal of JSON lines under the installation's `logs/` directory. The engine removes whole UTC days past the chosen retention and rotates the oldest file out at the chosen storage limit; Settings → Logs sets both, and they apply at the next engine start. The app's Diagnostics screen reads the journal directly, so it works while the engine is stopped. Trading evidence remains in operational SQLite.

There is no container deployment command in this repository. The old server procedures remain in Git history. Current runtime and release limits are in [validation](validation.md).
