# Contributing

Thanks for helping improve CopyTrading. The project has two code roots: `desktop/` for the desktop app and `engine/` for its bundled local Python engine (`app/` holds the build scripts and the previous SwiftUI app, which is being retired). The [PRD](docs/PRD.md) describes product intent; [architecture](docs/architecture.md) describes the current boundaries.

## Set up and check

Requirements and the first build are in the [README](README.md#install). `make doctor` tells you what your Mac is missing.

```sh
make dev
uvx pre-commit install   # Ruff and file hygiene before each commit
make check
```

To build and check the native app, run `make app` once to prepare the pinned runtime, then:

```sh
make desktop-check
make desktop-smoke
```

`make check` runs the engine suite with line and branch coverage (it fails under 80% and writes `dist/coverage/`), Ruff, Ty, and the app packaging-script tests. In `desktop/`, `npm run typecheck`, `npm test`, and `npm run build` check the app; `make desktop-build` builds the bundle. CI runs pre-commit, the engine checks, every Swift suite, and zizmor on each change, and publishes releases from tags ([releases](docs/releases.md)); it never uses real credentials.

## Changes and reports

The app is English only. Show engine codes in words and money and times in the formats the desktop app already uses; never show a raw code or an ISO timestamp ([desktop/README.md](desktop/README.md)).

Keep policy in `engine/src/copytrading_engine` domain and application modules; adapters own source, model, broker, SQLite, and notification effects. Preserve short SQLite transactions and durable delivery confirmation. Never call a model or broker from inside a database transaction. Test failure, restart, and cancellation paths when changing persistence or delivery.

Pull requests are squash-merged, so the PR title becomes the commit subject. Write it as one plain sentence under 72 characters that says what changed for the user or the code, for example "Accounts: a paused account says why it is paused". Put the why and the checks you ran in the description.

Use synthetic messages and mocked external clients in tests. Never commit credentials, private source messages, provider requests or responses, broker data, databases, or raw operational logs. Report bugs and propose features with the [issue forms](https://github.com/YZXBiz/copytrading/issues/new/choose). Send vulnerabilities privately using the instructions in [SECURITY.md](SECURITY.md).

An unsigned local build and passing checks do not establish release readiness. See [release instructions](docs/releases.md) for preview artifacts and [validation](docs/validation.md) for remaining product and distribution gates.
