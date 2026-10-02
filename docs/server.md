# Run the engine without the app

`copytrading-server` runs the same trading engine the Mac app runs, on a Mac or a Linux
server, without the app. It reads Discord, has your model read each post, checks your limits,
and trades at Alpaca exactly as the app does: the app and the server share every line of the
trading engine. Use it to keep copying while your Mac sleeps, or on a small always-on server.

| | Mac app | Server |
| --- | --- | --- |
| Setup | Getting Started and Connections | `copytrading.toml` |
| Keys | macOS Keychain | environment variables |
| Approvals | a sheet with Touch ID | `copytrading-server approve`, typed by you |
| Today, Activity, Accounts | the window | `copytrading accounts`, `copytrading activity` |
| Runs on | macOS 26, Apple Silicon | macOS or Linux with Python 3.14, or Docker |

> [!WARNING]
> Never point the app and a server at the same broker keys. Each would see the other's
> shares as unexplained and stop that account for your review. Use separate accounts, or run one of them.

## Install

With [uv](https://docs.astral.sh/uv/):

```sh
uv tool install --python 3.14 "git+https://github.com/YZXBiz/copytrading#subdirectory=engine"
```

This installs two commands: `copytrading-server` (run it) and `copytrading` (read and steer
it, also used by coding agents).

## Set up

```sh
copytrading-server init            # writes a commented copytrading.toml
```

Edit `copytrading.toml`: the Discord channels, the model, your accounts and their limits, and
each guru with the accounts they copy into. Every field is explained in the file. Then set the
keys it lists in your environment:

```sh
export COPYTRADING_DISCORD_TOKEN=…
export COPYTRADING_MODEL_API_KEY=…            # not needed for Ollama
export COPYTRADING_ALPACA_PAPER_MAIN_KEY=…    # one key and secret per account:
export COPYTRADING_ALPACA_PAPER_MAIN_SECRET=… # the account id in capitals, "-" becomes "_"
```

Keys never go in the file, so the file can be shared or kept in Git.

## Check, then run

```sh
copytrading-server check     # signs in to Discord, the model, and Alpaca; reads each example
copytrading-server run       # starts copying; Ctrl-C or SIGTERM pauses and stops cleanly
```

`check` saves nothing and places nothing. `run` repeats the check before it starts. New
accounts start with entries off, so nothing is bought until you turn them on:

```sh
copytrading-server entries enable paper-main
```

## Day to day

```sh
copytrading-server status               # copying, Discord, the model, each account
copytrading accounts                    # balances, positions, and the post behind each lot
copytrading activity --limit 10         # recent posts and what each account did
copytrading-server pause                # stop copying; `resume` checks the setup and restarts
copytrading-server proposals            # what an agent asked you to approve
copytrading-server approve p-4e1a9c…    # shows exactly what it does and asks you to type yes
```

The server prints a line when copying, an account, or the work done changes. Its full private
log is under the state folder's `logs/`, with keys removed.

## Coding agents

The server answers the same [agent contract](agent-control.md) as the app. `[agents] access`
in the file decides what agents may do: `off`, `read_pause` (the default), or `propose`, where
anything that could trade waits for `copytrading-server approve`. The `copytrading` command and
its MCP server find a running server on their own; set `COPYTRADING_STATE_ROOT` to the state
folder if you moved it.

## Where it keeps things

| | Default |
| --- | --- |
| macOS | `~/Library/Application Support/CopyTrading Server` |
| Linux | `$XDG_STATE_HOME/copytrading-server` (usually `~/.local/state/copytrading-server`) |

Choose another with `copytrading-server --state-dir DIR …`. Everything in it is owner-only.
It holds the SQLite trading records, the private log, and two sockets: `control/cli.sock` for
agents and `control/owner.sock` for you. Anyone who can run commands as your user can use the
owner socket, so run the server under its own user on a shared machine.

## Docker

```sh
cd engine
docker build -t copytrading-server .
docker run -d --name copytrading --restart unless-stopped \
  -v "$PWD/copytrading.toml:/config/copytrading.toml:ro" \
  -v copytrading-state:/state \
  --env-file copytrading.env \
  copytrading-server
docker exec copytrading copytrading-server entries enable paper-main
docker logs -f copytrading
```

`docker stop` sends SIGTERM, so the server pauses and finishes in-flight work before it exits.
`docker build --target test .` runs the engine's tests on Linux.

## Limits of this preview

- Windows is not supported yet: the server uses Unix sockets and file locks.
- There is no Touch ID on a server. The owner socket trusts the operating-system user.
- The server reads its setup when it starts. After editing the file, restart the server.
