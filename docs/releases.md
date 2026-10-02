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
point at a commit on `main` and the release not to exist yet. It runs the engine,
packaging, Swift, and native contract checks (`make desktop-check`), builds and
verifies the app and its records (`app/scripts/release.py`), wraps the app in the
drag-to-install image (`make dmg`), smoke-tests the released app, checks every
asset against the manifest and checksums, and publishes the prerelease with the
changelog section as its notes.

Versions are `MAJOR.MINOR.PATCH-alpha.N`, `beta.N`, or `rc.N`, and the core
version must match the app bundle and engine metadata.

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
