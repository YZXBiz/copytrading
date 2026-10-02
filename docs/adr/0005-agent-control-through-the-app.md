# ADR-0005: Agents control the app through a CLI and an MCP server, gated by the engine and the owner

## Status
Accepted, September 2026.

## Context
CopyTrading is a single-owner macOS app on one Mac. It supervises a local engine that trades real money. The owner wants to check and steer it from a terminal and from coding agents such as Claude Code, without clicking through the window. Other people and third-party clients never call it.

Only the app can reach the engine today. The app starts the engine with private inherited pipes (`host/pipe/server.py`), and an installation lock allows one engine. The app owns processes, UI and credentials. The engine owns durable operational decisions (`docs/architecture.md`).

An agent is a new kind of caller:
* It reads source text that strangers write in Discord, so a crafted message can try to steer it (prompt injection).
* It can see private account data, and Claude Code can reach the network. Together with untrusted content, that is Willison's "lethal trifecta".
* It can ask for approvals repeatedly, hoping the owner taps "Approve" out of fatigue.

Telling the agent to be careful stops none of this; only the interface can.

## Decision
1. **Two faces, one core.** `copytrading` is one executable.
   * Its commands form the CLI, for the owner, scripts, UI journeys, and agents through Bash.
   * `copytrading mcp` runs an MCP stdio server, for agents that benefit from tool discovery, typed schemas and per-tool permission rules.

   Both call the same client and return the same response models. MCP adds no operation the CLI lacks.
2. **The engine decides; the app relays.** A new engine package, `control`, owns:
   * the permission tiers
   * proposals and approval
   * rate and proposal limits
   * the audit trail
   * the response contract

   The app listens on an owner-only Unix socket and checks that the peer is the same macOS user. It passes each request to the engine as a single `control` pipe operation, together with the access level and lock state. A CLI caller therefore cannot reach any privileged engine operation.
3. **Tiers are fixed in code:**
   * **Read** runs immediately.
   * **Safer** (pause processing, pause an account) runs immediately, because it can only reduce risk.
   * **Approval** (resume an account, change recovery preference, confirm manual orders) only creates a proposal. It runs after the owner approves in the app with Touch ID or the device password. The approval is bound to the proposal's content digest.

   MCP tool annotations and Claude Code permission rules describe the same tiers. They are conveniences, not the guarantee.
4. **Approval never uses MCP elicitation.** Elicitation asks the client, and in an agent the model may answer. An approval must prove a person is present.
5. **Access is off by default**, and the owner chooses a level: *Read and pause*, or *Read, pause and propose*. Reads and proposals require an unlocked app. Pausing works whenever access is on.
6. **The protocol is versioned JSON lines, RPC style.** We own both ends and ship them in one bundle. Responses carry `schema_version`, and the published JSON Schema is the contract. A breaking change raises the major version; old versions are not kept.

## Alternatives considered
* **MCP only.** Rejected: shell scripts, UI journeys and plain terminals would lose access, and MCP adds nothing a CLI cannot do for them.
* **REST over localhost HTTP.** Rejected: we control both ends on one machine. HTTP adds a listener any local process can reach, plus CSRF-style browser risk, for no benefit.
* **Reading the SQLite databases directly.** Rejected: it bypasses the lock state and the audit trail, and cannot pause or propose.
* **Exposing the engine's pipe.** Rejected: the pipe carries credentials and privileged operations.
* **Tiers and proposals in the Swift app.** Rejected: proposals and audit are durable operational decisions, which the engine owns. Keeping the rules in Python gives one source of truth for the CLI, MCP and tests.

## Threat model (STRIDE)
| Threat | Example | Mitigation |
| --- | --- | --- |
| Spoofing | Another process under the owner's account calls the socket | Accepted within the macOS user boundary; approval needs Touch ID, which a process cannot fake |
| Spoofing | A process plants a fake socket at the path | The client checks that the path is a socket owned by the user, not a symlink, in a `0700` directory |
| Tampering | A proposal changes between display and approval | Approval carries the digest the owner saw; a mismatch is refused |
| Repudiation | "I never approved that" | The audit trail records caller PID and path, every proposal, and who approved or rejected it, and when |
| Information disclosure | Secrets or broker IDs leak to an agent | Responses use dedicated models without secrets, tokens or broker account numbers; source text is labelled untrusted |
| Denial of service | A looping agent floods the engine pipe | Bounded requests per window (`busy`), and the app caps concurrent connections |
| Denial of service / elevation | Approval spam hoping for a tired "Approve" | One pending proposal per action type; repeated rejections pause proposals (`cooling_down`) |
| Elevation of privilege | A read-only caller performs an action | An exhaustive tier table and access level check in the engine, backed by property and mutation tests |

## Consequences
* Positive: agents can monitor the app and stop trading quickly. Money-moving actions keep a person in the loop that prompt injection cannot bypass.
* Positive: there is one set of rules, in the engine, shared by the CLI, MCP and tests. The app change is a thin relay.
* Negative: the app must be running, and approval-tier actions need someone at the Mac.
* Negative: the MCP SDK and its dependencies enlarge the bundled runtime.
* Negative: backups taken before the audit component existed no longer match the schema catalog. This is consistent with the no-migration policy.
