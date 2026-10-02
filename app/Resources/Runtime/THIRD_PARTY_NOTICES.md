# Third-party runtime notices

These pins describe the native ARM64 runtime evaluated for the macOS desktop
candidate. They do not approve redistribution. Review the license and include
the required license text in any release package.

| Component | Version / platform | License | Artifact and integrity |
| --- | --- | --- | --- |
| CPython standalone | `3.14.7+20260924`, `aarch64-apple-darwin` | PSF-2.0. The [license text and history](https://docs.python.org/3/license.html) are also present as `python/lib/python3.14/LICENSE.txt` inside the pinned artifact. | [Astral python-build-standalone release archive](https://github.com/astral-sh/python-build-standalone/releases/download/20260924/cpython-3.14.7%2B20260924-aarch64-apple-darwin-install_only.tar.gz); SHA-256 `d3da099bb2bdd57e2f5ff8496cb9827f7d92eee332b09f8dc93706dabfc51a96`, matching the publisher's release asset digest. |

The standalone Python license notes that incorporated components can have
separate licenses. The exact redistribution bundle and all transitive notices remain a release
review gate. This file records the evaluated artifacts; it is
not a legal determination.
