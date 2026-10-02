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
Accounts    paper-main  entries enabled, recovery manual

$ copytrading accounts
paper-main (paper)  entries enabled, recovery manual, risk ready, exposure $2,184.00
  NVDA  app 12, external 0
    lot copy-3f9a1c0e5b7d2a8f6e4c1b9d0a7f3e2c5b8d1a6e  12 of 12 at $182.40  from alex  (discord:calls:101)

$ copytrading accounts pause paper-main
Paused new entries for paper-main.

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
| `accounts resume ACCOUNT` | `propose_resume_account` | Approval |
| `accounts recovery ACCOUNT PREFERENCE` | `propose_recovery_preference` | Approval |
| `manual confirm ACCOUNT --preview ID` | `propose_manual_order` | Approval |
| `schema` | — | Prints the response JSON Schema |

The first version deliberately leaves out several operations:
* **Starting processing**, because it needs Keychain secrets and the owner should read the validation report in the window.
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

## Access and lock

Access is chosen in Settings → Agent Access (Nothing / Read and pause / Read, pause, and ask for approval) and is **off** by default. The choice is saved in `agent-access.json` (mode `0600`) in the state folder. Changing it requires owner authentication. When access is off, the socket does not exist.

| | Off | Read and pause | Read, pause and propose |
| --- | --- | --- | --- |
| Read | — | unlocked only | unlocked only |
| Safer | — | always | always |
| Approval | — | refused (`forbidden`) | unlocked only |

Locking or quitting the app discards pending proposals.

## Proposals

A proposal has a kind (`resume_account`, `set_recovery`, `confirm_manual_order`), a typed subject, a SHA-256 digest of that subject, a fixed `command_id`, and a state:

```text
pending ──approve(digest)──► approved ──► succeeded | failed | outcome_unknown
pending ──► rejected | expired | discarded
```

- **Expiry.** A proposal expires after 5 minutes, or earlier when its manual preview expires.
- **Approve once.** Approval is accepted once, only while the proposal is pending, and only with a matching digest. The action runs once, under the fixed `command_id`, so a retry cannot double-submit.
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
- **Dedicated response models.** These live in `control/wire.py`, not the engine's internal views, so engine refactors cannot silently break scripts. They never contain credentials, tokens or broker account identifiers. Discord text appears only in fields named `untrusted_source_text`; what the interpreter read from it is in `understood_as` (action, symbol, price, fraction).
- **Published schema.** `copytrading schema` prints the JSON Schema, and a committed copy (`engine/tests/control/contract/schema-v1.json`) fails the tests when the contract changes without a deliberate update.
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
| 6 | Engine could not complete it: `not_found`, `unavailable`, or a failed or unknown outcome |
| 7 | Proposal rejected, expired or discarded |
| 10 | Approval pending; the proposal ID is printed |

## Audit

The `control_audit` table in `application.db` records every decision:
* time
* caller PID and path
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
| `mcp_server.py` (I/O) | MCP tools over the client; the only module that imports `mcp` |
| `__main__.py` | `python -m copytrading_engine.control` |

The pipe server gains app-only operations:
* `control`, which relays one CLI or MCP line
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
- **UI journey J18** drives the real window: the command exits 3 before access is allowed; after choosing Read and pause it reads status, pauses processing, and is refused a proposal (exit 5); the request shows in the recent list; choosing Nothing makes it exit 3 again. Rejected, expired, and discarded proposals (exit 7) are covered by the CLI tests.
