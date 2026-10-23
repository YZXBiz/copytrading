# Agent control: CLI and MCP

How the owner and coding agents (Claude Code, scripts) check and steer a running CopyTrading through the `copytrading` CLI and its MCP server. The decision, the alternatives and the threat model are in [ADR-0005](adr/0005-agent-control-through-the-app.md).

The owner turns agent access on in Settings → Agent Access; approvals appear as a sheet in the app window and ask for Touch ID or the device password.

### Try it

1. In CopyTrading, open Settings → Agent Access and choose **Read and pause** or **Read, pause, and ask for approval** (the app asks you to confirm).
2. Press **Copy Setup Command** and run it, which registers the MCP server with Claude Code:
   `claude mcp add copytrading -- "/Applications/CopyTrading.app/Contents/Helpers/copytrading" mcp`
3. Or run the command directly: `"/Applications/CopyTrading.app/Contents/Helpers/copytrading" status`.

The command looks in `~/Library/Application Support/CopyTrading` unless `COPYTRADING_STATE_ROOT` points elsewhere. When the app's socket is absent it uses a running [server](server.md)'s instead; there, access comes from `[agents] access` in `copytrading.toml` and approvals from `copytrading-server approve`.

## What it looks like

```console
$ copytrading status
Engine      Ready
Processing  Running
Accounts    paper-main  copying on, recovery manual

$ copytrading accounts
paper-main (paper)  copying on, recovery manual, risk ready, exposure $2,184.00
  NVDA  app 12, external 0
    lot copy-3f9a1c0e5b7d2a8f6e4c1b9d0a7f3e2c5b8d1a6e  12 of 12 at $182.40  from alex  (discord:calls:101)

$ copytrading accounts pause paper-main
paper-main: copying off, recovery manual.

$ copytrading accounts resume paper-main
Waiting for approval in CopyTrading: proposal p-4e1a9c, expires 16:42.
$ echo $?
10

$ copytrading activity --limit 5 --json | jq '.ok.items[0].parse_status'
"accepted"
```

In Claude Code, run `claude mcp add copytrading -- "/Applications/CopyTrading.app/Contents/Helpers/copytrading" mcp`. Tools such as `get_status`, `list_accounts`, `pause_account` and `propose_resume_account` then appear.

## How a request flows

```text
Claude Code ──(MCP stdio)──► copytrading mcp ┐
Claude Code ──(Bash)───────► copytrading …   ├─► control client ──socket──► app ──pipe──► engine control package
owner / scripts / journeys ─► copytrading …  ┘   (one response        (same-user     (tiers, proposals,
                                                     contract)             relay)          limits, audit)
```

1. The CLI or MCP server sends one JSON line to `<state root>/control/cli.sock`.
2. The app checks that the peer is the same macOS user, and caps concurrent connections. It then forwards the line to the engine as the pipe operation `control`, adding the access level, the lock state, and the caller's PID and executable path.
3. The engine's `control` package decides:
   * Is the operation allowed at this access level and lock state?
   * Is the caller within its rate limit?
   * Does it run now, or become a proposal?

   It records the decision in the audit trail and returns one JSON line, which the app relays back.
4. For a proposal, the app shows an approval sheet. **Approve** asks for Touch ID or the device password, then sends `approve_proposal` with the digest it displayed. The engine runs the action exactly once.

## Commands and tools

| CLI | MCP tool | Tier |
| --- | --- | --- |
| `status` | `get_status` | Read |
| `accounts [--before ID] [--limit N]` | `list_accounts` | Read |
| `activity [--before SEQ] [--limit N]` | `list_activity` | Read |
| `events ACCOUNT [--before SEQ] [--limit N]` | `list_account_events` | Read |
| `manual list ACCOUNT SOURCE` | `list_manual_commands` | Read |
| `manual show ACCOUNT COMMAND` | `get_manual_command` | Read |
| `manual preview ACCOUNT --correction ID --instruction N` | `preview_manual_order` | Read (stores a preview; places nothing) |
| `proposals`, `proposals show ID`, `proposals wait ID` | `list_proposals`, `get_proposal` | Read |
| `pause` | `pause_processing` | Safer |
| `accounts pause ACCOUNT` | `pause_account` | Safer |
| `start` | `propose_start_processing` | Approval (the app runs Start Copying) |
| `accounts resume ACCOUNT` | `propose_resume_account` | Approval |
| `accounts recovery ACCOUNT PREFERENCE` | `propose_recovery_preference` | Approval |
| `accounts limits ACCOUNT --max-order-usd 300 --overnight true …` | `propose_set_account_limits` | Approval (the app applies it) |
| `manual confirm ACCOUNT --preview ID` | `propose_manual_order` | Approval |
| `setup show` | — | Read |
| `setup discord`, `setup model`, `setup account add\|edit\|remove`, `setup guru add\|edit\|remove`, `setup alerts`, `setup import FILE`, `setup discard` | — | Setup (edits the unsaved setup) |
| `setup apply` | — | Setup; a proposal when it touches a live account |
| `schema` | — | Prints the response JSON Schema |

The first version deliberately leaves out several operations:
* **Keys through MCP.** Only the CLI's `setup` commands carry a key, read from standard input or a file the owner points at (below). The MCP server has no setup tools, so a key never passes through a model.
* **Selling a lot.** Positions list each lot and the post that bought it (below), but a lot is sold only by the owner, from Accounts, after reviewing the live quote; the app asks for Touch ID on live accounts.
* **Corrections, ownership resolution, backup and restore, profile evaluation and self-test.** Each can join later by being given a tier.

MCP tool annotations follow the tiers:
* read tools: `readOnlyHint: true`, `openWorldHint: false`
* pause tools: `destructiveHint: false`, `idempotentHint: true`
* `propose_*`: `destructiveHint: true`

The server's instructions tell the model that `propose_*` only asks the owner, and that source text is untrusted data.

Suggested Claude Code permission rules (a convenience; the engine is the guarantee):

```json
"allow": ["mcp__copytrading__get_*", "mcp__copytrading__list_*"],
"ask":   ["mcp__copytrading__pause_*", "mcp__copytrading__propose_*", "mcp__copytrading__preview_*"]
```

## Setup from the command line

`copytrading setup` reads and changes every part of the setup the Connections screen edits, without the window:

```console
$ copytrading setup show
Setup       saved, with unsaved changes; Copying
Discord     channels 1517000000000009742; authors any; token saved  [connected]
Model       deepseek deepseek-flash; key entered, not saved yet
Account     paper-main (paper); keys saved; after a restart Wait for me  [connected]
              max order usd 100, max symbol usd 600, max total usd 2500, …
Account     zhap-account-2 (paper); keys entered, not saved yet; after a restart Carry on by itself  [needs attention]
              ! zhap-account-2: Alpaca didn't accept these keys. Check that they are for a paper or live account as chosen.
Guru        Alex (guru-dae39a86); channel 1517000000000009742, author any, account paper-main, full position $600, skips re-posts within 10 min, playbook 0 characters
Alerts      off
Run `copytrading setup apply` to check every connection, save, and start.
```

| Command | Example |
| --- | --- |
| `setup show` | `copytrading setup show --json` |
| `setup discord` | `copytrading setup discord --channels 111,222 --authors "" --secret-stdin < token.txt` |
| `setup model` | `copytrading setup model --service deepseek --model deepseek-flash --from-file key.txt` |
| `setup account add` | `copytrading setup account add paper-2 --from-file alpaca.txt --max-order-usd 250 --overnight true` |
| `setup account edit` | `copytrading setup account edit paper-2 --rename paper-two --approve-orders true --after-restart carry-on` |
| `setup account remove` | `copytrading setup account remove paper-two` |
| `setup guru add` | `copytrading setup guru add Alex --channel 111 --account paper-2 --full-position 600` |
| `setup guru edit` | `copytrading setup guru edit Alex --author 333 --playbook-file alex.txt --repeat-window 0` |
| `setup guru remove` | `copytrading setup guru remove guru-dae39a86` (by name or the ID their channel gives them) |
| `setup alerts` | `copytrading setup alerts --on --service telegram --chat-id -100123 --secret-stdin` |
| `setup import` | `copytrading setup import ~/Desktop/setup.txt` (Import Setup's label format, or a `trading-configuration.json` CopyTrading saved) |
| `setup apply` | `copytrading setup apply` (copying that is paused stays paused) |
| `setup apply --start` | `copytrading setup apply --start` (also starts copying, a first setup included) |
| `setup discard` | `copytrading setup discard` |

How it works:
* **One draft, one save path.** Edits change the app's unsaved setup, the same one Connections shows (the window marks it as changed, and Discard there drops it). `setup apply` runs Start Copying's connection checks on it and saves it. While copying runs, it checks first, pauses, starts again, and turns copying back on only for the accounts that were copying; limits alone save without a check, as the account sheet saves them. While copying is paused, it checks and saves without starting, and says "Saved. Copying stays paused, as you left it."; the next Start Copying checks the saved setup again. `setup apply --start` is Start Copying itself: it checks, saves, and starts copying that is paused or has never started, so a whole first setup can be done without the window. Starting copying into a live account is always a proposal, and starting it still asks for Touch ID. It reports each check, and a failure names the account, guru, or connection, what happened, and the command that fixes it. The app is still the only writer of `trading-configuration.json` and the Keychain.
* **Keys.** `--secret-stdin` reads the key from standard input (asked for without echo at a terminal) and `--from-file PATH` from a file. An account takes two lines, the API key ID then the secret. A key file must be a regular file of at most 64 KB, opened once; a pipe or device is refused. No option takes a key as an argument, nothing prints one, and `setup show` says only `saved`, `missing`, `entered` (typed, not saved yet), or `not needed`. Before reading any key or setup file the CLI checks that the Mac app answers: it refuses a server's socket, then sends `get_setup` and reads the key only once the app has answered it. Requests carrying keys go to the app, which answers them itself and never sends them to the engine; a server answers setup requests without passing them to its engine. A request over 64 KB is refused, by the CLI before sending and by the app with "request too large".
* **The setup's own rules.** `--after-restart wait-for-me|carry-on` is the account sheet's After a restart (Wait for me, the default, or Carry on by itself), saved with the account's limits as `policy.recovery_preference` (`manual` or `automatic`), and `setup show` shows it on each account. A guru's ID is the one their channel gives them, as in the window and the engine (`GuruIdentity.id`, `route_keys.guru_for_channel`); no request names one, a name that reads as a guru ID is refused, and a guru with no channel yet has no ID. Each channel copies one guru, so adding a guru, or moving one, onto a channel another guru reads is refused with the other guru's name. `--full-position` is the guru's own full position in their account (a 1/6 call buys a sixth of it); until it is set, the account's maximum per stock is used.
* **Importing a saved setup.** `setup import` also reads a setup CopyTrading saved (`trading-configuration.json`, or the `configuration` object in it). One saved by an earlier version runs through the same one-way upgrade the app runs at launch (`SetupUpgrade`, ADR-0013); a setup from before upgrades existed (version 7 and older) or from a newer CopyTrading is refused with its version, and nothing is imported. As with Import Setup, every account comes in as paper, a file holds no keys, and an account the file saved before the after-restart choice existed waits for you after a restart.
* **A saved key stays with its address.** Changing where the model is served (`--base-url`) needs the key in the same request, and an apply refuses a setup whose model address moved from the saved one without a new key.
* **The engine still decides.** For each setup request the app sends the engine the pipe operation `authorize_setup` with the operation's name and, for an apply, what it does to live accounts (`made_live`, `new_live_keys`, `changed_live`, `starts_live`), never a key. Setup changes are approval-tier and need their own permission: **Read, pause, and ask for approval** plus **Allow setup changes from the command line** (below), and an unlocked app. Without it every edit and apply is refused as `forbidden` with a message naming where to turn it on; `setup show` stays on the read tier. Setup requests count toward the rate limit and are recorded in the audit trail with their caller, a line the app could not read included. An apply that touches no live account runs at once; one that makes an account live, saves keys for one, changes one's limits or the gurus copying into it, or starts copying into one becomes an `apply_setup` proposal. An account is known by the name it was saved under, so renaming a live account, or giving a paper account a live account's name, counts as making it live. The app takes the facts and the draft's signature together before asking the engine, so an edit made while the engine decides is never part of what it allowed: a paper apply then fails as `conflict`, and approving the proposal fails as `setup_changed`. Approving applies exactly the setup the owner was shown; starting copying into a live account then asks for Touch ID again, as Start Copying does. `app/Resources/Contracts/agent-setup-apply-facts.json` holds the cases the app and the CLI tests both check.
* **Live limits never save from a sheet.** An account sheet saves only its own account's limits, and never a live account's limits an agent changed; those wait for an approved `setup apply` or the owner's own Start Copying.
* **Locking** drops the unsaved setup, keys included, as it does in the window.
* A headless server is set up in `copytrading.toml`, so it refuses setup requests as `unavailable`.

### When `setup apply` has no clear outcome

* **No answer in time.** The CLI waits up to `--timeout` seconds (300 by default). If the app has not answered, it exits 6 and says the outcome is not known: the apply may still be checking. `copytrading setup show` then tells: no unsaved changes means the setup was saved, and `copying` shows whether copying runs.
* **A start not confirmed yet.** If copying started but the engine has not confirmed the new setup, the result is `failed` with "Copying is starting the new setup but hasn't confirmed it yet"; the app keeps checking and `setup show` reads the outcome once it settles. An apply while a start is settling refuses with "A start is still settling".
* **An approved proposal.** `proposals wait ID` reports `succeeded`, `failed` (with `failed_checks`, `failed`, or `setup_changed`), or `outcome_unknown` (`app_did_not_report`) when the app did not report within five minutes.
* **Running it again is safe.** Apply is idempotent on the same draft: once a setup is saved, applying it again finds nothing to apply (`unchanged`) and neither saves nor starts again; `--start` starts copying once. Rerun `setup apply` after any of the cases above.

## Access and lock

Access is chosen in Settings → Agent Access (Nothing / Read and pause / Read, pause, and ask for approval) and is **off** by default. The choice is saved in `agent-access.json` (mode `0600`) in the state folder. Changing it requires owner authentication. When access is off, the socket does not exist.

| | Off | Read and pause | Read, pause and propose |
| --- | --- | --- | --- |
| Read | — | unlocked only | unlocked only |
| Safer | — | always | always |
| Approval | — | refused (`forbidden`) | unlocked only |

Locking or quitting the app discards pending proposals.

**Allow setup changes from the command line** is a separate switch in Settings → Agent Access, shown under "Read, pause, and ask for approval". It is **off** by default, saved beside the access choice (`setup_changes` in `agent-access.json`; a file saved before it existed reads as off), and turning it on or off asks for Touch ID like any access change. An agent the owner allowed to read, pause, and propose can therefore never change the Discord token, the model service and key, accounts, keys, or gurus unless the owner turned this on; live accounts still wait for approval either way. The app sends the switch to the engine with every request (`setup_changes` in the request context), and the engine's policy refuses setup changes without it. The in-app assistant has no setup tools.

## Proposals

A proposal has a kind (`resume_account`, `set_recovery`, `confirm_manual_order`, `set_account_limits`, `start_processing`, `apply_setup`), a typed subject, a SHA-256 digest of that subject, a fixed `command_id`, and a state:

```text
pending ──approve(digest)──► approved ──► succeeded | failed | outcome_unknown
pending ──► rejected | expired | discarded
```

- **Expiry.** A proposal expires after 5 minutes, or earlier when its manual preview expires.
- **Approve once.** Approval is accepted once, only while the proposal is pending, and only with a matching digest. The action runs once, under the fixed `command_id`, so a retry cannot double-submit.
- **Changes the app performs.** `start_processing` runs the app's own Start Copying (every connection check, and Touch ID for a live account) and is refused with `conflict` while copying already runs; its failures come back as `failed_checks` or `failed`. `set_account_limits` changes the setup the app has saved, which the engine cannot write. Approving it leaves the proposal `running`; the app then applies the values over its saved setup exactly as the account sheet's limit save does (no check, no pause) and tells the engine how it went with `complete_proposal`. The app refuses with a code and changes nothing when you have unsaved edits (`unsaved_changes`), a start is in flight (`busy`), or the account is unknown (`not_found`). If the app never reports, the proposal ends as `outcome_unknown` (`app_did_not_report`) after five minutes. A headless server has no app, so it refuses the request as `unavailable`. The engine checks every value with the account settings model before the owner sees it, and the sheet shows each setting's value now and after. Any setting the account sheet's limits accept can be set. `apply_setup` is app-performed the same way: approving it runs Start Copying on the setup the app kept for that proposal and reports `failed_checks`, `failed`, or `setup_changed` when it did not take effect.
- **`outcome_unknown`.** Used when the action's result cannot be confirmed (for example, a broker timeout). The caller then checks with `manual show` or `events`; the fixed command ID makes that lookup exact.
- **Limits.** One pending proposal per kind. Three rejections within 10 minutes stop new proposals for 10 minutes (`cooling_down`).
- **Rate limit.** At most 30 control requests per 10 seconds (`busy`).
- **Proposals stay in memory.** A proposal lasts minutes and dies with the lock or the app. Durable facts live elsewhere: manual command outcomes in the execution ledger, and decisions in the audit trail.

## Contract

Requests and responses are JSON lines of at most 64 KiB, one request per connection.

```json
{"schema_version": 1, "request_id": "…", "operation": "pause_account", "account_id": "paper-main"}
{"schema_version": 1, "request_id": "…", "ok": {"type": "account_control", …}}
{"schema_version": 1, "request_id": "…", "error": {"code": "locked", "message": "Unlock CopyTrading to read account data."}}
```

- **Positions and lots.** Each account's positions carry `owned_qty` (bought by CopyTrading), `external_qty` (held outside it), and `lots`: one entry per copied buy with `lot_id`, the `source_id` and `guru_id` of the post that bought it, `posted_at`, `untrusted_source_text` (an excerpt of that post), `bought_at`, `original_qty`, `remaining_qty`, and `average_price`.
- **Dedicated response models.** These live in `control/wire.py`, not the engine's internal views, so engine refactors cannot silently break scripts. They never contain credentials, tokens or broker account identifiers. Discord text appears only in fields named `untrusted_source_text`; what the interpreter read from it is in `understood_as` (action, symbol, price, fraction, and `usd_amount` for a buy sized in dollars).
- **Published schema.** `copytrading schema` prints the JSON Schema, and a committed copy (`engine/tests/control/contract/schema-v1.json`) fails the tests when the contract changes without a deliberate update.
- **Compatibility rule.** The `copytrading` CLI, the MCP server, and the app ship together in one bundle (`CopyTrading.app/Contents/Helpers/copytrading`), so within a release `SCHEMA_VERSION` 1 may grow additively: new operations, new optional request fields, new response types and subject kinds. Any removal or rename of an operation, field, type, or value raises `SCHEMA_VERSION`. A client that receives a well-formed response it cannot read (a type or kind it does not know) rejects it with `ProtocolMismatch` and says "this copytrading CLI is older than the app; use the one inside CopyTrading.app" rather than a generic failure; anything that is not a contract response at all is reported as outside the contract.
- **Error codes:** `access_off`, `locked`, `forbidden`, `invalid_request`, `not_found`, `unavailable`, `busy`, `cooling_down`, `proposal_limit`, `conflict`, `expired`, `rejected`.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Done |
| 1 | Unexpected failure |
| 2 | Usage error or `invalid_request` |
| 3 | App not running, or access off |
| 4 | App locked |
| 5 | Refused: `forbidden`, `busy`, `cooling_down`, `proposal_limit`, `conflict` |
| 6 | Engine could not complete it: `not_found`, `unavailable`, or a failed or unknown outcome, including a request sent with no answer in time |
| 7 | Proposal rejected, expired or discarded |
| 10 | Approval pending; the proposal ID is printed |

## Audit

The `control_audit` table in `application.db` records every decision:
* time
* caller PID and path (for every setup request too, including a line the app refused before asking)
* operation, tier, outcome
* proposal ID
* for approvals and rejections, the app as actor

It keeps the newest 10,000 rows and stores identifiers, never arguments with free text. Settings → Agent Access shows recent entries.

## The in-app assistant

The assistant in the app's side panel (⌘J) shares these tiers, rate limits, proposal limits, and audit trail. Each of its tools is a normal control request, handled at the "read, pause, and propose" level because you are present and the app is unlocked. The audit trail records it as an agent request from the caller "CopyTrading Assistant" (no new actor or schema), so its requests are told apart in Settings → Agent Access, and its proposals ask for approval under "The assistant is asking for approval". It reads real data and pauses copying or one account when you ask; anything that could trade is only a proposal that waits for your Touch ID. What you choose in Settings → Agent Access governs outside agents only, not the assistant. It answers in the language you ask in, and otherwise in the app's language (English or 简体中文); tickers, account names, and dollar amounts stay as they are, and quoted Discord posts keep their own language.

## Code layout

`engine/src/copytrading_engine/control/` is a flat package (ADR-0002). Its I/O modules are named; the rest is policy.

| Module | Holds |
| --- | --- |
| `wire.py` | Request union, response models, error codes, `SCHEMA_VERSION`, JSON Schema export (depends only on Pydantic) |
| `policy.py` | Tiers, access levels, the decision function, and the rate window |
| `proposals.py` | Proposal state machine and the in-memory proposal book with its limits |
| `service.py` | `ControlService`: validates requests, applies policy, runs reads and actions through ports, and maps engine views to wire models |
| `sqlite.py` (I/O) | `CONTROL_AUDIT_SCHEMA` and the audit store |
| `client.py` (I/O) | Socket discovery and checks, one request per connection |
| `cli.py` (I/O) | Argument parsing, text and JSON output, exit codes |
| `cli_setup.py` (I/O) | `copytrading setup …`: its arguments, reading keys from stdin or a file, and its text output |
| `mcp_server.py` (I/O) | MCP tools over the client; the only module that imports `mcp` |
| `__main__.py` | `python -m copytrading_engine.control` |

The pipe server gains app-only operations:
* `control`, which relays one CLI or MCP line
* `authorize_setup`, which decides a setup request the app answers itself, without its keys
* `list_proposals`
* `approve_proposal`
* `reject_proposal`
* `discard_proposals`

`bootstrap.py` wires the service. `test_architecture.py` allows `host → control` and allows `control` to import only `shared` plus the execution and trading domain and presentation layers. Only `mcp_server` may import `mcp`, and the client-side modules may import only `wire`.

## Tests

- **Policy:**
  - table tests for every operation, access level and lock state
  - a Hypothesis property that approval-tier operations never run without an approved proposal
- **Proposals:** a Hypothesis state machine over create, approve, reject, expire and discard, checking that each action runs at most once, and only after approval with the right digest before expiry.
- **Service:**
  - with fake engine ports, reads leak no broker identity or secrets
  - pauses run
  - proposals call nothing until approved
  - `busy`, `cooling_down` and `locked` behave as specified
  - the audit trail records each decision
- **Contract:** golden request and response files plus the committed JSON Schema.
- **CLI and MCP** run against a fake app socket that relays to a real `PipeServer` with fake trading services, covering output, `--json` and every exit code.
- **Mutation probes** (`make check-mutations`) cover making resume "safer", dropping the digest check, and allowing a second approval.
- **Setup:** setup changes are refused without **Allow setup changes from the command line**, every setup request is audited with its caller, a newer app's response gets the older-CLI message, an apply with no answer says the outcome is unknown, and two applies of the same draft save and start once (`applyingTheSameSetupTwiceSavesAndStartsOnce`). `test_setup_cli.py` drives every `setup` command through the socket to a stand-in for the app that asks the real pipe server's `authorize_setup`, covering keys from stdin, files and a terminal, refusals, exit codes, and live proposals; the Swift `agent setup contracts` check decodes the same request fixtures (`agent-setup-requests.json`) and emits the response fixtures, and `agent setup from the command line` runs the app's handler against its own draft, Keychain store, and Start Copying, including an approved live apply. `agentControlWithTheEngine` runs the real CLI through the relay to the real engine.
- **UI journey J18** drives the real window: the command exits 3 before access is allowed; after choosing Read and pause it reads status, pauses processing, and is refused a proposal (exit 5); the request shows in the recent list; choosing Nothing makes it exit 3 again. Rejected, expired, and discarded proposals (exit 7) are covered by the CLI tests.
