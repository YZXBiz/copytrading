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

Installed copies update through Sparkle ([ADR-0009](adr/0009-updates-with-sparkle.md)).
A tagged release signs its DMG with Sparkle's `sign_update` and the private key in
the `SPARKLE_ED_PRIVATE_KEY` repository secret, adds itself to `appcast.xml`
(`app/scripts/appcast.py`), and pushes that feed to the `appcast` branch after the
GitHub release exists. The app reads the feed from
`https://raw.githubusercontent.com/YZXBiz/copytrading/appcast/appcast.xml` and checks
each download against the public key in its `Info.plist`.

The private key is also in the owner's login Keychain ("Sparkle EdDSA key for
CopyTrading updates"), because a repository secret cannot be read back. Copies from
before 0.1.0-alpha.4 have no updater and need that one DMG installed by hand.

## Release assets

- `CopyTrading-<version>.dmg` and its `.sha256`: the drag-to-install disk image
  most people download.
- `CopyTrading-v<version>-macos-arm64.zip`: the same app as a ZIP.
- `copytrading-source-v<version>.tar.gz`: the source of the tagged commit.
- `sbom.cyclonedx.json`: a CycloneDX inventory of the app's dependencies.
- `THIRD_PARTY_NOTICES.md` and `THIRD_PARTY_LICENSES.zip`: runtime notices and
  license texts, also inside the app under `Contents/Resources`.
- `release-manifest.json`: version, tag, commit, platform, signing status, and
  asset hashes.
- `SHA256SUMS`: checksums for the ZIP, source, and records.

Verify a download from the folder that holds it:

```sh
shasum -a 256 -c SHA256SUMS
shasum -a 256 -c CopyTrading-<version>.dmg.sha256
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
