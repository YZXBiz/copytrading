import { copyFileSync, mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { type Engine, createApi } from "../electron/main/api"
import { SecretStore } from "../electron/main/secrets"
import { SETUP_FILE, SetupFile } from "../electron/main/setup-file"

const dirs: string[] = []
afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })))
const cipher = { encrypt: (text: string) => Buffer.from(text).reverse(), decrypt: (data: Buffer) => Buffer.from(data).reverse().toString() }

function harness(subject: Record<string, unknown> = { kind: "resume_account", account_id: "zhap-account-2" }) {
  const sent: { op: string; params: Record<string, unknown> }[] = []
  const engine: Engine = {
    request: async (op, params = {}) => {
      sent.push({ op, params })
      if (op === "list_proposals") return { proposals: [{ proposal_id: "p-0123456789ab", state: "pending", digest: "d".repeat(64), subject }] }
      if (op === "restore_candidate_status") return { candidate: { candidate_id: "cand-1", account_ids: ["zhap-account-2"] } }
      return { type: "ok", proposal: {}, candidate_id: "cand-1" }
    },
  }
  const dir = mkdtempSync(join(tmpdir(), "settings-api-"))
  dirs.push(dir)
  copyFileSync(join(__dirname, "fixtures", SETUP_FILE), join(dir, SETUP_FILE))
  const secrets = new SecretStore(join(dir, "secrets.bin"), cipher)
  const asked: string[] = []
  const api = createApi({
    engine,
    setup: new SetupFile(dir),
    secrets,
    confirm: async (text) => (asked.push(text), true),
    diagnosticsDir: dir,
    pick: async (kind) => (kind === "backup-destination" ? "/tmp/b.zip" : null),
  })
  return { api, secrets, sent, asked }
}

describe("restorePreflight", () => {
  it("sends the keys from the key store with the environment from the saved setup, whatever the page sent", async () => {
    const h = harness()
    h.secrets.merge({ brokers: [{ account_id: "zhap-account-2", key: "KEY-FROM-STORE", secret: "SECRET-FROM-STORE" }] })
    await h.api.act("restorePreflight", { candidate_id: "cand-1", accounts: [{ account_id: "x", key: "page", secret: "page" }] })
    const request = h.sent.find((r) => r.op === "restore_preflight")!
    expect(request.params).toEqual({
      candidate_id: "cand-1",
      accounts: [{ account_id: "zhap-account-2", environment: "paper", key: "KEY-FROM-STORE", secret: "SECRET-FROM-STORE" }],
    })
  })

  it("refuses, naming the account, when its keys are not saved, and asks the engine nothing", async () => {
    const h = harness()
    const result = await h.api.act("restorePreflight", { candidate_id: "cand-1" })
    expect(result).toMatchObject({ ok: false, error: expect.stringContaining("zhap-account-2") })
    expect(h.sent.some((r) => r.op === "restore_preflight")).toBe(false)
  })

  it("refuses a candidate the engine does not hold", async () => {
    const h = harness()
    expect(await h.api.act("restorePreflight", { candidate_id: "other" })).toMatchObject({ ok: false })
  })
})

describe("approveProposal", () => {
  it("refuses a request only the app can carry out, so it is not left running", async () => {
    for (const subject of [
      { kind: "set_recovery", account_id: "zhap-account-2", preference: "manual" },
      { kind: "set_account_limits", account_id: "zhap-account-2", changes: [] },
      { kind: "start_processing" },
      { kind: "apply_setup" },
    ]) {
      const h = harness(subject)
      expect(await h.api.act("approveProposal", { proposal_id: "p-0123456789ab" })).toMatchObject({ ok: false })
      expect(h.asked).toEqual([])
      expect(h.sent.some((r) => r.op === "approve_proposal")).toBe(false)
    }
  })

  it("still approves one the engine finishes itself", async () => {
    const h = harness()
    expect(await h.api.act("approveProposal", { proposal_id: "p-0123456789ab" })).toMatchObject({ ok: true })
    expect(h.sent.some((r) => r.op === "approve_proposal")).toBe(true)
  })
})

describe("file dialogs and the journal", () => {
  it("returns the chosen path, or null for Cancel", async () => {
    const h = harness()
    expect(await h.api.act("chooseBackupDestination", undefined)).toEqual({ ok: true, value: "/tmp/b.zip" })
    expect(await h.api.act("chooseRestoreArchive", undefined)).toEqual({ ok: true, value: null })
  })

  it("reads the journal without asking the engine", async () => {
    const h = harness()
    expect(await h.api.read("readDiagnostics", undefined)).toEqual({ ok: true, value: { entries: [], bytes: 0 } })
    expect(h.sent).toEqual([])
  })
})
