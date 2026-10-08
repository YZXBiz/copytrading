<p align="center">
  <img src="docs/assets/app-icon.png" alt="" width="96">
</p>

<h1 align="center">CopyTrading</h1>

<p align="center">
  <em>Copy the traders you trust, inside limits you set.</em>
</p>

<p align="center">
  <a href="https://github.com/YZXBiz/copytrading/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://github.com/YZXBiz/copytrading/actions/workflows/ci.yml/badge.svg?branch=main" alt="Checks"></a>
  <a href="https://coverage-badge.samuelcolvin.workers.dev/redirect/YZXBiz/copytrading"><img src="https://coverage-badge.samuelcolvin.workers.dev/YZXBiz/copytrading.svg" alt="Coverage"></a>
  <a href="https://github.com/YZXBiz/copytrading/releases"><img src="https://img.shields.io/github/v/release/YZXBiz/copytrading?include_prereleases&label=release&color=blue" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS%2026%2B-Apple%20silicon-black?logo=apple" alt="macOS 26 or later on Apple silicon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://github.com/YZXBiz/copytrading/releases/download/v0.1.0-alpha.8/CopyTrading-0.1.0-alpha.8.dmg"><img src="https://img.shields.io/badge/Download_for_macOS-0.1.0--alpha.8-1d1d1f?style=for-the-badge&logo=apple&logoColor=white" alt="Download CopyTrading for macOS" height="36"></a>
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <strong>Not financial advice.</strong> CopyTrading is software, not an adviser. Trading can lose money, and you are responsible for every order it places.
</p>

CopyTrading is a native macOS app that reads the stock calls traders post on Discord, turns each one into an exact order, checks it against your limits, and places it with your Alpaca account. Everything runs on your Mac.

> [!WARNING]
> **Not financial advice.** Nothing in this project, including the app, its assistant, and the traders it copies, is investment, financial, legal, or tax advice, and nobody here recommends any trade. Trading can lose some or all of your money. You alone choose whom to copy and what limits to set, and you are responsible for every order placed in your accounts. The software is provided as is, without warranty ([MIT license](LICENSE)).
>
> **Developer preview.** CopyTrading has not been qualified for live trading. Start with an Alpaca paper account, and see [validation](docs/validation.md) for what has and has not been proven.

<p align="center">
  <a href="docs/assets/today.png"><img src="docs/assets/today.png" alt="Today: the day's change, the equity curve, what happened to each post, and limit usage (sample data)" width="860"></a>
</p>

<details>
<summary>More screenshots</summary>
<br>
<table>
  <tr>
    <td width="33%"><a href="docs/assets/accounts.png"><img src="docs/assets/accounts.png" alt="Accounts: balance, limits, and positions opened into the posts that bought them (sample data)"></a></td>
    <td width="33%"><a href="docs/assets/people.png"><img src="docs/assets/people.png" alt="People: each trader's latest call, how their recent posts went, and the accounts that copy them (sample data)"></a></td>
    <td width="33%"><a href="docs/assets/connections.png"><img src="docs/assets/connections.png" alt="Connections: Discord, the model that reads posts, and alerts (sample data)"></a></td>
  </tr>
  <tr>
    <td align="center"><sub><b>Accounts</b>: every position traces to its posts</sub></td>
    <td align="center"><sub><b>People</b>: who you copy and how it went</sub></td>
    <td align="center"><sub><b>Connections</b>: Discord, the model, alerts</sub></td>
  </tr>
</table>
</details>

## Features

- **Posts become exact orders.** A model you choose reads each post, and every ticker, price, and fraction must appear in the post itself, so it cannot invent a number.
- **Your limits, per account.** Daily loss, per-order, per-symbol, and total exposure limits are checked before every copied buy. New accounts start with entries off.
- **Many traders, many accounts.** Each trader-to-account link has its own sizing, and paper and live accounts sit side by side.
- **Every position traces to its post.** Each copied buy is kept as a lot that names the post behind it, and you can sell any lot on its own.
- **An assistant that cannot trade on its own.** ⌘J answers from your real posts and accounts. Anything that could place an order waits for your Touch ID.
- **Private by design.** Keys stay in the macOS Keychain. The app talks to Discord, your model provider, and your broker, plus Telegram if you turn on alerts and GitHub when you check for updates.

Works with a dozen hosted model services, local models through Ollama, or any OpenAI-compatible address, in English or 简体中文.

## Install

You need an Apple silicon Mac running macOS 26 or later.

1. **[Download CopyTrading for macOS](https://github.com/YZXBiz/copytrading/releases/download/v0.1.0-alpha.8/CopyTrading-0.1.0-alpha.8.dmg)** (55 MB).
2. Open the DMG and drag **CopyTrading** into **Applications**.
3. Open CopyTrading. Preview builds are not yet notarized by Apple, so the first time macOS blocks it: go to **System Settings → Privacy & Security** and choose **Open Anyway**. You only do this once.

Every release lists SHA-256 checksums, and [releases](docs/releases.md) explains how to verify a download.

**Or build from source** with [uv](https://docs.astral.sh/uv/) and the Xcode Command Line Tools:

```sh
git clone https://github.com/YZXBiz/copytrading.git
cd copytrading
make app
```

`make app` checks your Mac, downloads a pinned and checksummed runtime, builds the app, and opens it. The first build takes a few minutes.

## Get started

The app opens on **Getting Started**, a checklist that ticks itself as you go. Nothing is saved or traded until you press **Start Copying**.

Everything is set up in **Connections**, top to bottom:

1. **Discord**: the channels to read and your Discord token.
2. **Interpreter**: the model that reads posts, and its API key.
3. **Broker accounts**: an Alpaca **paper** account.
4. **Gurus**: press **Learn from Channel**, review the playbook it drafts, and set how much each account puts in.
5. Press **Start Copying**. It checks every connection first, and starts only when they all pass.

Every field that needs a key or an ID has a **Where do I find this?** link. When you are ready, turn on entries in **Accounts** and watch the first post arrive in **Activity**.

## How it works

<p align="center">
  <a href="docs/assets/copytrading-workflow.png"><img src="docs/assets/copytrading-workflow.png" alt="CopyTrading workflow: Discord capture, grounded model interpretation, parallel account routing and risk checks, Alpaca execution, broker reconciliation and lot history, with separate owner-approved assistant controls" width="100%"></a>
  <br>
  <sub><a href="docs/assets/copytrading-workflow.png">View the full-resolution diagram</a></sub>
</p>

A SwiftUI app supervises one local Python engine. The engine owns every decision, keeps it in SQLite, and reconciles with the broker after a crash or sleep, so a signal that expires while the app is closed never becomes a late order. [Architecture](docs/architecture.md) has the details and the [ADRs](docs/adr/) record why.

## Command line and agents

The `copytrading` CLI and MCP server let you, a script, or a coding agent read the running app and pause it. Anything that could trade becomes a proposal you approve with Touch ID in the app.

```console
$ copytrading status
Engine      Ready
Processing  Running
Accounts    paper-main  entries enabled, recovery manual

$ copytrading accounts resume paper-main
Waiting for approval in CopyTrading: proposal p-4e1a9c, expires 16:42.
```

See [agent control](docs/agent-control.md) for the commands, permission tiers, and threat model.

The engine also runs without the app, on a Mac or a Linux server, so copying continues while your Mac sleeps. `copytrading-server` reads a `copytrading.toml` file and keys from environment variables, and a Docker image is included. See [Run the engine without the app](docs/server.md).

## Documentation

| | |
| --- | --- |
| [PRD](docs/PRD.md) | Who CopyTrading is for and what it must do |
| [Architecture](docs/architecture.md) · [Engine structure](docs/engine-structure.md) · [ADRs](docs/adr/) | How the pieces fit, and why |
| [Agent control](docs/agent-control.md) · [Server](docs/server.md) | The `copytrading` CLI and MCP server, and running the engine without the app |
| [Acceptance](docs/acceptance.md) · [Validation](docs/validation.md) | What "working" means, and the evidence so far |
| [Operations](docs/operations.md) · [Releases](docs/releases.md) | Developer commands and preview builds |
| [Changelog](CHANGELOG.md) | What changed in each release |

## Contributing

Run `make doctor` to check your Mac, then `make check` for the engine's 1,200+ tests, Ruff, and Ty. [CONTRIBUTING.md](CONTRIBUTING.md) covers the native app checks and conventions. Ask questions in [Discussions](https://github.com/YZXBiz/copytrading/discussions), report bugs with the [issue forms](https://github.com/YZXBiz/copytrading/issues/new/choose), and report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
