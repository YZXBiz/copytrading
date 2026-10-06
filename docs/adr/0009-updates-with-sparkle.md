# ADR-0009: Updates come through Sparkle

## Status
Accepted, October 2026.

## Context
CopyTrading had its own updater: it read GitHub's `releases/latest`, downloaded a signed `.pkg`
named in a JSON manifest, staged it, and swapped the app bundle through a recovery coordinator.
None of it ever worked for a real release. GitHub hides pre-releases from `releases/latest`, so
every alpha answered 404, and the release workflow publishes a DMG and a ZIP, never the `.pkg`
and manifest the updater asked for. Its installer also expected a Developer ID publisher, which
the project does not have and will not buy.

Mac apps outside the App Store almost all update through Sparkle (iTerm2, Rectangle, Maccy, Ice,
MonitorControl). Sparkle does not need Apple's paid program: each download is signed with an
EdDSA key whose public half ships in the app, and an update downloaded by Sparkle is not
quarantined, so an un-notarized app updates without a Gatekeeper warning.

## Decision
1. **Sparkle 2, pinned exactly** (2.10.0), linked only into the app's entry point. The screens
   see an `AppUpdating` protocol; previews and tests use a stand-in, and debug builds run by UI
   journeys never start the updater.
2. **One feed, published by the release workflow.** A tagged release signs its DMG with
   `sign_update` (Sparkle's pinned, checksum-verified tools) and the private key from the
   `SPARKLE_ED_PRIVATE_KEY` secret, adds itself to `appcast.xml` (`app/scripts/appcast.py`), and,
   after the GitHub release exists, publishes the feed on the `appcast` branch. The app reads
   it from `raw.githubusercontent.com`. Nothing is committed to `main`, and no Pages site is
   needed.
3. **Every build has a build number.** `CFBundleVersion` is the commit count of the built
   history, which only grows on `main`; `CFBundleShortVersionString` is the full release version
   (`0.1.0-alpha.4`). Sparkle offers a release whose build number is higher than the installed
   app's.
4. **The owner decides when to install.** The app checks once a day (Settings → Updates can turn
   that off) and Check for Updates… is in the app menu and Settings; Sparkle shows the release
   notes and installs only when asked. A quit through Sparkle stops the engine the same way any
   quit does.
5. **The private key is backed up outside GitHub.** A repository secret cannot be read back, and
   losing the key would strand every installed copy, so the owner's login Keychain holds it as
   "Sparkle EdDSA key for CopyTrading updates" (service `https://sparkle-project.org`, account
   `copytrading`), where Sparkle's own tools look.

## Consequences
* The hand-written updater, its installer, recovery coordinator, and their tests are gone.
* Releases before this one cannot update themselves; their owners install the next DMG by hand
  once, and every later release arrives through Check for Updates….
* If the key is ever rotated, the old public key must stay in the app for one release (Sparkle's
  key rotation), or installed copies will refuse the new signatures.
