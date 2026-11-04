import { randomUUID } from "node:crypto"
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import type { PendingRestoreCandidate } from "../shared/contract"
import type { Drain } from "../electron/main/engine/launch"
import { RuntimePaths } from "../electron/main/engine/paths"
import { RestoreCoordinator, RestoreError, preflightAccounts } from "../electron/main/restore"
import type { Secrets } from "../electron/main/secrets"

const roots: string[] = []
afterEach(() => roots.splice(0).forEach((root) => rmSync(root, { recursive: true, force: true })))

const REVISION = "6F1C2D3E-0000-4000-8000-000000000001"
const keys: Secrets = { discord_token: "d", provider_api_key: "p", brokers: [{ account_id: "acct-1", key: "KEY", secret: "SECRET" }] }

/**
 * A stand-in engine over a real installation folder: it holds a restore candidate and the gate file the way the engine does,
 * answers only while it runs, and reports the generation the pointer names when it starts.
 */
function rig(opts: { blockers?: string[]; drain?: Drain; failStartOn?: number; failComplete?: boolean; failAbortReply?: boolean; held?: { revision: string | null; secrets: Secrets } } = {}) {
  const root = mkdtempSync(join(tmpdir(), "restore-"))
  roots.push(root)
  const paths = new RuntimePaths(root)
  const installation = paths.installationIdentity()
  const previous = paths.activeGeneration().id
  const gate = join(root, ".restore-manual-disabled")
  const log: string[] = []
  let candidate: PendingRestoreCandidate | null = null
  let running = true
  let starts = 0
  let active = previous

  const status = () => (candidate ? { ...candidate, active_generation: active } : null)
  const engine = async (op: string, params: Record<string, unknown> = {}): Promise<unknown> => {
    if (!running) throw new Error("The engine is not running.")
    log.push(op)
    switch (op) {
      case "restore_candidate_status":
        return { type: "restore_candidate_status", candidate: status() }
      case "prepare_restore_candidate": {
        const id = randomUUID()
        mkdirSync(join(root, "generations", id), { mode: 0o700 })
        writeFileSync(gate, "")
        candidate = {
          candidate_id: id,
          previous_generation: previous,
          active_generation: previous,
          installation_id: installation,
          environment_ids: ["paper:acct-1"],
          account_ids: ["acct-1"],
          credential_references: [REVISION],
          candidate_valid: true,
        }
        return { type: "restore_candidate_prepared", candidate_id: id, staging: params.staging_id }
      }
      case "restore_preflight":
        return {
          candidate_id: params.candidate_id,
          eligible: !opts.blockers,
          checked_account_count: 1,
          blockers: opts.blockers ?? [],
          completion_token: opts.blockers ? null : "token",
          accounts: params.accounts,
        }
      case "complete_restore_candidate":
        if (opts.failComplete) {
          running = false
          throw new Error("lost")
        }
        rmSync(gate, { force: true })
        candidate = null
        running = false // completing stops the gated engine
        return {}
      case "abort_restore_candidate":
        rmSync(gate, { force: true })
        candidate = null
        if (opts.failAbortReply) throw new Error("reply lost")
        return {}
      default:
        throw new Error(`unexpected ${op}`)
    }
  }
  const coordinator = new RestoreCoordinator({
    paths,
    request: engine,
    secrets: () => opts.held ?? { revision: REVISION, secrets: keys },
    stopRuntime: async () => {
      log.push("stop")
      const was = running
      running = false
      return was ? (opts.drain ?? "acknowledged") : "no_live_engine"
    },
    startRuntime: async () => {
      starts += 1
      log.push("start")
      if (opts.failStartOn === starts) throw new Error("did not start")
      active = paths.activeGeneration().id
      running = true
    },
  })
  return { paths, coordinator, log, previous, status, get active() { return paths.activeGeneration().id }, gate }
}

const stage = { stagingId: "stage-1", matchesInstallation: true }

describe("activate", () => {
  it("stops, switches to the restored data, checks the broker, completes, and restarts on it", async () => {
    const r = rig()
    await expect(r.coordinator.activate(stage)).resolves.toEqual({ status: "restored" })
    expect(r.active).not.toBe(r.previous)
    expect(existsSync(r.gate)).toBe(false)
    expect(r.status()).toBeNull()
    // The engine was down for the switch, up to check the candidate, down after completing, and up on the restored data.
    expect(r.log).toEqual(["restore_candidate_status", "prepare_restore_candidate", "restore_candidate_status", "stop", "start", "restore_candidate_status", "restore_preflight", "complete_restore_candidate", "stop", "start", "restore_candidate_status"])
  })

  it("sends the keys from the store, with each account's environment from the candidate", async () => {
    const sent: unknown[] = []
    const r = rig()
    const original = r.coordinator as unknown as { deps: { request: (op: string, p?: Record<string, unknown>) => Promise<unknown> } }
    const request = original.deps.request
    original.deps.request = async (op, p) => (op === "restore_preflight" && sent.push(p?.accounts), request(op, p))
    await r.coordinator.activate(stage)
    expect(sent).toEqual([[{ account_id: "acct-1", environment: "paper", key: "KEY", secret: "SECRET" }]])
  })

  it("puts the old data back, and says the broker did not match, when the check is blocked", async () => {
    const r = rig({ blockers: ["broker_state_mismatch"] })
    await expect(r.coordinator.activate(stage)).resolves.toEqual({ status: "blocked", blockers: ["broker_state_mismatch"] })
    expect(r.active).toBe(r.previous)
    expect(existsSync(r.gate)).toBe(false)
    expect(r.status()).toBeNull()
    expect(r.log).not.toContain("complete_restore_candidate")
    expect(r.log).toContain("abort_restore_candidate")
  })

  it("switches nothing when the old engine did not confirm it finished", async () => {
    const r = rig({ drain: "unconfirmed" })
    await expect(r.coordinator.activate(stage)).rejects.toMatchObject({ code: "previousEngineDrainUnconfirmed" })
    expect(r.active).toBe(r.previous)
    expect(r.status()).toBeNull()
  })

  it("rolls back when the engine will not start on the restored data", async () => {
    const r = rig({ failStartOn: 1 })
    await expect(r.coordinator.activate(stage)).rejects.toMatchObject({ code: "candidateStartFailed" })
    expect(r.active).toBe(r.previous)
    expect(r.status()).toBeNull()
  })

  it("says so, and leaves the engine down, when the rollback itself cannot finish", async () => {
    const r = rig({ failStartOn: 1 })
    const startsBefore = (r.coordinator as unknown as { deps: { startRuntime: () => Promise<void> } }).deps
    const start = startsBefore.startRuntime
    let calls = 0
    startsBefore.startRuntime = async () => {
      calls += 1
      if (calls >= 1) throw new Error("still down")
      return start()
    }
    await expect(r.coordinator.activate(stage)).rejects.toMatchObject({ code: "rollbackIncomplete" })
  })

  it("rolls back, then reports the failure, when completing was not confirmed and the gate still holds", async () => {
    const r = rig({ failComplete: true })
    await expect(r.coordinator.activate(stage)).rejects.toMatchObject({ code: "completionUnconfirmed" })
    expect(r.active).toBe(r.previous)
    expect(r.status()).toBeNull()
  })

  it("treats a lost abort reply as an abort only if the gate and the pointer agree", async () => {
    const r = rig({ blockers: ["broker_state_mismatch"], failAbortReply: true })
    await expect(r.coordinator.activate(stage)).resolves.toMatchObject({ status: "blocked" })
    expect(r.active).toBe(r.previous)
  })

  it("will not restore a backup from a different installation, or one it was never shown", async () => {
    const r = rig()
    await expect(r.coordinator.activate({ stagingId: "s", matchesInstallation: false })).rejects.toMatchObject({ code: "candidateUnavailable" })
    expect(r.log).toEqual(["restore_candidate_status"])
  })

  it("refuses a second restore while one runs", async () => {
    const r = rig()
    const first = r.coordinator.activate(stage)
    await expect(r.coordinator.activate(stage)).rejects.toMatchObject({ code: "busy" })
    await first
    expect(r.coordinator.isRunning).toBe(false)
  })

  it("will not start a new restore over a half-finished one it was not told about", async () => {
    const r = rig()
    await (r.coordinator as unknown as { deps: { request: (op: string, p: object) => Promise<unknown> } }).deps.request("prepare_restore_candidate", { staging_id: "x" })
    await expect(r.coordinator.activate(stage)).rejects.toMatchObject({ code: "candidateConflict" })
  })
})

describe("resuming and rolling back", () => {
  it("finishes a half-done restore the page names, by its candidate id", async () => {
    const r = rig()
    const id = (await (r.coordinator as unknown as { deps: { request: (op: string, p: object) => Promise<{ candidate_id: string }> } }).deps.request("prepare_restore_candidate", { staging_id: "x" })).candidate_id
    await expect(r.coordinator.activate({ candidateId: id })).resolves.toEqual({ status: "restored" })
    expect(r.active).toBe(id)
  })

  it("refuses to resume under another candidate's id", async () => {
    const r = rig()
    await (r.coordinator as unknown as { deps: { request: (op: string, p: object) => Promise<unknown> } }).deps.request("prepare_restore_candidate", { staging_id: "x" })
    await expect(r.coordinator.activate({ candidateId: "other" })).rejects.toMatchObject({ code: "candidateConflict" })
  })

  it("rolls back a candidate left by an earlier run, starting the engine to find it", async () => {
    const r = rig()
    const deps = (r.coordinator as unknown as { deps: { request: (op: string, p: object) => Promise<{ candidate_id: string }>; stopRuntime: () => Promise<Drain> } }).deps
    const { candidate_id } = await deps.request("prepare_restore_candidate", { staging_id: "x" })
    await deps.stopRuntime()
    await r.coordinator.rollback(candidate_id)
    expect(r.active).toBe(r.previous)
    expect(existsSync(r.gate)).toBe(false)
    expect(r.status()).toBeNull()
  })

  it("rolls back a candidate the engine reports while it runs", async () => {
    const r = rig()
    const deps = (r.coordinator as unknown as { deps: { request: (op: string, p: object) => Promise<{ candidate_id: string }> } }).deps
    const { candidate_id } = await deps.request("prepare_restore_candidate", { staging_id: "x" })
    await r.coordinator.rollback(candidate_id)
    expect(r.active).toBe(r.previous)
  })

  it("refuses to roll back a candidate it cannot find", async () => {
    const r = rig()
    await expect(r.coordinator.rollback("nothing")).rejects.toMatchObject({ code: "candidateUnavailable" })
  })
})

describe("preflightAccounts", () => {
  const candidate = (over: Partial<PendingRestoreCandidate> = {}): PendingRestoreCandidate => ({
    candidate_id: "c",
    previous_generation: "p",
    active_generation: "a",
    installation_id: "inst",
    environment_ids: ["live:acct-1", "paper:acct-2"],
    account_ids: ["acct-1", "acct-2"],
    credential_references: [REVISION],
    candidate_valid: true,
    ...over,
  })
  const held = {
    revision: REVISION.toLowerCase(),
    secrets: { ...keys, brokers: [...keys.brokers, { account_id: "acct-2", key: "K2", secret: "S2" }] },
  }
  const code = (run: () => unknown) => {
    try {
      run()
    } catch (error) {
      return error instanceof RestoreError ? error.code : "other"
    }
    return "none"
  }

  it("takes environments from the candidate and keys from the store", () => {
    expect(preflightAccounts(candidate(), "inst", held)).toEqual([
      { account_id: "acct-1", environment: "live", key: "KEY", secret: "SECRET" },
      { account_id: "acct-2", environment: "paper", key: "K2", secret: "S2" },
    ])
  })

  it("needs the keys to belong to the revision the backup's setup names", () => {
    expect(code(() => preflightAccounts(candidate(), "inst", { ...held, revision: "other" }))).toBe("credentialsUnavailable")
    expect(code(() => preflightAccounts(candidate(), "inst", { ...held, revision: null }))).toBe("credentialsUnavailable")
    expect(code(() => preflightAccounts(candidate({ credential_references: [] }), "inst", held))).toBe("credentialsUnavailable")
    expect(code(() => preflightAccounts(candidate({ credential_references: [REVISION, "x"] }), "inst", held))).toBe("credentialsUnavailable")
  })

  it("needs keys for every account", () => {
    expect(code(() => preflightAccounts(candidate(), "inst", { ...held, secrets: { ...keys } }))).toBe("credentialsUnavailable")
  })

  it("refuses a candidate that is invalid, from another installation, or whose accounts and environments disagree", () => {
    expect(code(() => preflightAccounts(candidate({ candidate_valid: false }), "inst", held))).toBe("candidateInvalid")
    expect(code(() => preflightAccounts(candidate(), "elsewhere", held))).toBe("candidateInvalid")
    expect(code(() => preflightAccounts(candidate({ environment_ids: ["live:acct-1"] }), "inst", held))).toBe("candidateInvalid")
    expect(code(() => preflightAccounts(candidate({ environment_ids: ["demo:acct-1", "paper:acct-2"] }), "inst", held))).toBe("candidateInvalid")
    expect(code(() => preflightAccounts(candidate({ environment_ids: ["live:acct-1", "paper:acct-3"] }), "inst", held))).toBe("candidateInvalid")
  })

  it("needs no keys for a backup with no accounts", () => {
    expect(preflightAccounts(candidate({ account_ids: [], environment_ids: [], credential_references: [] }), "inst", { revision: null, secrets: { discord_token: "", provider_api_key: "", brokers: [] } })).toEqual([])
  })
})
