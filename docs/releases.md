# Developer preview releases

The macOS developer preview targets Apple Silicon and macOS 26 or later. The
first release in this repository is `v0.1.0-alpha.2`. Preview builds are not
signed with a Developer ID and are not notarized. Install them manually for evaluation; the app updater does not trust
these preview packages. macOS may warn or block an unsigned download.

## Build a preview

Use a clean checkout of the exact source commit and a prepared ARM64 runtime:

```sh
UV_PYTHON=/path/to/arm64/python3.14 make release RELEASE_VERSION=0.1.0-alpha.3
```

The command checks that the version is a prerelease, its core version matches
the app bundle and engine metadata, and the checkout is clean. It builds and
verifies the app, adds commit provenance, packages it with macOS `ditto`,
extracts and verifies the ZIP, and creates the source and dependency records.
It does not create a Git tag or publish a release.

Then wrap the verified app in the disk image people download:

```sh
make dmg RELEASE_VERSION=0.1.0-alpha.3
```

`make dmg` extracts the app from the release ZIP, checks its signature, lays out the
drag-to-install window from `app/Resources/DMG/` with a pinned `dmgbuild`, verifies
the image, and writes its SHA-256 next to it. Update the README's download link to
the new image when you publish.

## Release assets

Each draft release contains:

- `CopyTrading-<version>.dmg` and its `.sha256`: the drag-to-install disk image
  most people download, holding the same app as the ZIP.
- `CopyTrading-v<version>-macos-arm64.zip`: the app bundle, not notarized.
- `copytrading-source-v<version>.tar.gz`: source archive for the exact
  commit recorded in `release-manifest.json`.
- `sbom.cyclonedx.json`: CycloneDX dependency inventory for the app bundle.
- `THIRD_PARTY_NOTICES.md` and `THIRD_PARTY_LICENSES.zip`: collected runtime
  notices and available license text. The app ZIP also contains notices at
  `Contents/Resources/THIRD_PARTY_NOTICES.md` and license material at
  `Contents/Resources/ThirdPartyLicenses`, including the CPython license.
- `release-manifest.json`: version, tag, commit, target platform, signing
  status, and asset hashes.
- `SHA256SUMS`: SHA-256 checksums for every other release asset.

Verify downloaded assets from the directory containing them:

```sh
shasum -a 256 -c SHA256SUMS
```

The JSON manifest and checksums describe provenance and integrity; they are
not a signed attestation. The release workflow accepts prerelease versions
only, verifies its selected commit is on `main`, builds and verifies all
assets, and creates a draft prerelease after the build succeeds. It does not
publish stable releases or update the app's signed-package trust configuration.

## Redistribution review

The app bundles one native runtime, CPython (PSF-2.0); its license text ships
inside the app. Python dependency license files are collected from the built
runtime when present; texts supplied for distributions that ship none are in
[`release-materials`](release-materials/). Missing or ambiguous
license metadata, all transitive notices, and the product's redistribution
obligations remain a review gate. This inventory is evidence for that review,
not a legal determination or certification.
