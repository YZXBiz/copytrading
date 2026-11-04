# Releases

CopyTrading ships developer previews for Apple silicon Macs on macOS 26 or later.
GitHub Actions builds and publishes every release from a tag; nothing is built or
uploaded by hand. Preview builds are not signed with a Developer ID and not
notarized, so macOS asks for **Open Anyway** on first launch.

## Cut a release

1. Open a pull request that adds the version's section to
   [CHANGELOG.md](../CHANGELOG.md), headed `## <version> — developer preview`, and
   points the README's download links at `v<version>/CopyTrading-<version>.dmg`.
   The section becomes the release notes.
2. When it is merged, tag the merge commit and push the tag:

   ```sh
   git tag v0.1.0-alpha.2 origin/main
   git push origin v0.1.0-alpha.2
   ```

The [Release workflow](../.github/workflows/release.yml) then requires the tag to
point at a commit on `main`, which already passed CI, and the release not to exist
yet. It builds and verifies the app and its records (`app/scripts/release.py`),
wraps the app in the drag-to-install image (`make dmg`), smoke-tests the released
app, checks every asset against the manifest and checksums, and publishes the
prerelease with the changelog section as its notes. Last, it signs the DMG for
Sparkle and publishes the update feed (below), so installed copies find it.

Pull requests that change the release scripts, the workflow, the toolchain pin, or
the changelog run the same workflow as a dry run: it builds the newest changelog
version and stops before publishing, so a broken release fails on the pull request
instead of on the tag.

Versions are `MAJOR.MINOR.PATCH-alpha.N`, `beta.N`, or `rc.N`, and the core
version must match the app bundle and engine metadata. The built app shows the full
version (`CFBundleShortVersionString`) and carries the commit count of its history as
its build number (`CFBundleVersion`), which only grows on `main`.

## Updates

The app is Electron (`desktop/`), built by `app/scripts/build_desktop.py` into
`CopyTrading.app` with the pinned CPython and the engine inside
(`Contents/Resources/Runtime`, `Contents/Resources/Engine`). Its bundle id is
`dev.copytrading.app`, so it opens the same data folder as the SwiftUI app.

Installed copies update with `electron-updater` from the GitHub releases of
`YZXBiz/copytrading` (`Contents/Resources/app-update.yml`). Every release carries
`latest-mac.yml`, which names the app ZIP with its SHA-512; the app checks 30 seconds
after launch and every six hours, and **Check for Updates…** in the app menu checks
at once. It asks in a native dialog, downloads, remembers whether copying was on, and
relaunches; the next launch starts a paper-only setup again (`update.resumesCopying`
in the SwiftUI app). A throwaway data folder (`COPYTRADING_STATE_ROOT`) never offers
an update.

macOS installs an update only when the new app is signed by the identity that signed
the old one. Release builds are sealed ad hoc, which has no identity, so an installed
copy cannot install one in place: it says so and points to the release page, and the
DMG replaces the app by hand. A signing identity that stays the same from release to
release would change that; none is set up, and the release workflow does not use one.

Copies still running the SwiftUI app update through Sparkle
([ADR-0009](adr/0009-updates-with-sparkle.md)): a tagged release also signs its DMG
with Sparkle's `sign_update` and the private key in the `SPARKLE_ED_PRIVATE_KEY`
repository secret, adds itself to `appcast.xml` (`app/scripts/appcast.py`), and pushes
that feed to the `appcast` branch after the GitHub release exists. That is how they
move to the Electron app. The private key is also in the owner's login Keychain
("Sparkle EdDSA key for CopyTrading updates"). The step goes away with the SwiftUI app.

## The app's data folder

The built app runs its engine on `~/Library/Application Support/CopyTrading`, through
the generation pointer, as the SwiftUI app does; its own state (the key store) is in
`desktop/` beside it. Development and tests never get that folder: the engine runs on a
fresh folder under the temp directory, and `assertThrowaway` refuses the owner's.
`COPYTRADING_STATE_ROOT=<existing folder under $TMPDIR>` runs the built app on a
throwaway folder, and `COPYTRADING_SMOKE=1` with it quits 0 once the page has loaded and
the engine has answered (`make desktop-smoke`).

## Release assets

- `CopyTrading-<version>.dmg` and its `.sha256`: the drag-to-install disk image
  most people download.
- `CopyTrading-v<version>-macos-arm64.zip`: the same app as a ZIP.
- `copytrading-source-v<version>.tar.gz`: the source of the tagged commit.
- `latest-mac.yml`: the update feed `electron-updater` reads, naming the ZIP and its SHA-512.
- `sbom.cyclonedx.json`: a CycloneDX inventory of the app's dependencies.
- `THIRD_PARTY_NOTICES.md` and `THIRD_PARTY_LICENSES.zip`: runtime notices and
  license texts, also inside the app under `Contents/Resources`.
- `release-manifest.json`: version, tag, commit, platform, signing status, and
  asset hashes.
- `SHA256SUMS`: checksums for the ZIP, source, and records.

Verify a download from the folder that holds it. For the DMG, download its
`.sha256` file next to it:

```sh
shasum -a 256 -c CopyTrading-<version>.dmg.sha256
```

For the ZIP, source, or records, download `SHA256SUMS`; `--ignore-missing`
skips the files you did not download:

```sh
shasum -a 256 -c --ignore-missing SHA256SUMS
```

The manifest and checksums describe provenance and integrity; they are not a
signed attestation.

## Build a release locally

`make release RELEASE_VERSION=<version>` followed by `make dmg
RELEASE_VERSION=<version>` produces the same assets from a clean checkout of a
committed tree, for trying the pipeline before tagging. Local builds are for
inspection only; published assets always come from the workflow.

## Redistribution review

The app bundles one native runtime, CPython (PSF-2.0); its license text ships
inside the app. Python dependency license files are collected from the built
runtime when present; texts supplied for distributions that ship none are in
[`release-materials`](release-materials/). Missing or ambiguous license metadata,
all transitive notices, and the product's redistribution obligations remain a
review gate. This inventory is evidence for that review, not a legal
determination or certification.
