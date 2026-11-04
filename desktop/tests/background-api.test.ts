import { copyFileSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import type { AgentAccess, RestorePreview } from "../shared/contract"
import { type Engine, createApi } from "../electron/main/api"
import { Prefs } from "../electron/main/prefs"
import { SecretStore } from "../electron/main/secrets"
import { SETUP_FILE, SetupFile } from "../electron/main/setup-file"

const dirs: string[] = []
afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })))
const cipher = { encrypt: (text: string) => Buffer.from(text).reverse(), decrypt: (data: Buffer) => Buffer.from(data).reverse().toString() }

const preview: RestorePreview = {
  format_version: 1, created_at: "2026-11-02T18:20:00Z", installation_id: "i", matches_installation: true, environment_ids: ["paper:zhap-account-2"],
  account_ids: ["zhap-account-2"], credential_references: [], staging_id: "stage-1", members: [],
}

function harness(answer: boolean, over: { preview?: RestorePreview; candidate?: unknown } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "bg-api-"))
  dirs.push(dir)
  copyFileSync(join(__dirname, "fixtures", SETUP_FILE), join(dir, SETUP_FILE))
  const calls: string[] = []
  const asked: string[] = []
  const engine: Engine = {
    request: async (op) => {
      if (op === "preview_restore") return { type: "restore_preview", preview: over.preview ?? preview }
      if (op === "restore_candidate_status") return { candidate: over.candidate ?? null }
      return { type: "ok" }
    },
  }
  const setup = new SetupFile(dir)
  const api = createApi({
    engine,
    setup,
    secrets: new SecretStore(join(dir, "secrets.bin"), cipher),
    confirm: async (text) => (asked.push(text), answer),
    agents: {
      state: () => ({ access: "propose", listening: true, problem: null }),
      set: async (access: AgentAccess) => (calls.push(`agents:${access}`), { access, listening: access !== "off", problem: null }),
    },
    restore: {
      activate: async (input) => (calls.push(`activate:${JSON.stringify(input)}`), { status: "restored" }),
      rollback: async (id) => void calls.push(`rollback:${id}`),
    },
    prefs: new Prefs(dir),
    readers: { attach: async () => {} },
  })
  return { api, calls, asked, dir, setup }
}

describe("activateRestore", () => {
  it("asks about the backup main was shown, then restores it, whatever else the page claims", async () => {
    const h = harness(true)
    await h.api.act("previewRestore", { archive_path: "/b.zip" })
    const result = await h.api.act("activateRestore", { staging_id: "stage-1", matches_installation: true, account_ids: ["x"] })
    expect(result).toEqual({ ok: true, value: { status: "restored" } })
    expect(h.asked).toEqual(["Replace this Mac's CopyTrading records with the backup (zhap-account-2)?\n\nCopying pauses while it restores. If anything doesn't match your broker's records, nothing is replaced."])
    expect(h.calls).toEqual(['activate:{"stagingId":"stage-1","matchesInstallation":true}'])
  })

  it("restores nothing when the owner says no", async () => {
    const h = harness(false)
    await h.api.act("previewRestore", { archive_path: "/b.zip" })
    expect(await h.api.act("activateRestore", { staging_id: "stage-1" })).toEqual({ ok: false, error: "Cancelled.", cancelled: true })
    expect(h.calls).toEqual([])
  })

  it("refuses a backup it was never shown, without asking", async () => {
    const h = harness(true)
    expect(await h.api.act("activateRestore", { staging_id: "stage-1" })).toMatchObject({ ok: false, error: "Open the backup again to restore it." })
    expect(h.asked).toEqual([])
    expect(h.calls).toEqual([])
  })

  it("refuses a backup from a different installation, without asking", async () => {
    const h = harness(true, { preview: { ...preview, matches_installation: false } })
    await h.api.act("previewRestore", { archive_path: "/b.zip" })
    expect(await h.api.act("activateRestore", { staging_id: "stage-1" })).toMatchObject({ ok: false, error: expect.stringContaining("different installation") })
    expect(h.asked).toEqual([])
  })

  it("refuses while typed keys or a saved setup are held in memory, since they belong to the data being replaced", async () => {
    const typed = harness(true)
    await typed.api.act("previewRestore", { archive_path: "/b.zip" })
    await typed.api.act("setSecrets", { discord_token: "SENTINEL-typed-token-1" })
    expect(await typed.api.act("activateRestore", { staging_id: "stage-1" })).toMatchObject({ ok: false, error: "Finish starting or stopping copying, then restore." })
    expect(typed.asked).toEqual([])
    expect(typed.calls).toEqual([])

    const saved = harness(true)
    await saved.api.act("previewRestore", { archive_path: "/b.zip" })
    const { configuration } = JSON.parse(readFileSync(join(saved.dir, SETUP_FILE), "utf8"))
    saved.setup.save(configuration, "f".repeat(64))
    expect(await saved.api.act("activateRestore", { staging_id: "stage-1" })).toMatchObject({ ok: false, error: "Finish starting or stopping copying, then restore." })
    expect(saved.calls).toEqual([])
  })

  it("finishes a half-done restore the engine holds, and no other", async () => {
    const h = harness(true, { candidate: { candidate_id: "cand-1", account_ids: ["zhap-account-2"] } })
    expect(await h.api.act("activateRestore", { candidate_id: "cand-1" })).toMatchObject({ ok: true })
    expect(h.calls).toEqual(['activate:{"candidateId":"cand-1"}'])
    const other = harness(true, { candidate: { candidate_id: "cand-1", account_ids: [] } })
    expect(await other.api.act("activateRestore", { candidate_id: "cand-2" })).toMatchObject({ ok: false })
    expect(other.calls).toEqual([])
  })
})

describe("rollbackRestore", () => {
  it("undoes a restore only after the owner says yes", async () => {
    const no = harness(false)
    expect(await no.api.act("rollbackRestore", { candidate_id: "c" })).toMatchObject({ cancelled: true })
    expect(no.calls).toEqual([])
    const yes = harness(true)
    expect(await yes.api.act("rollbackRestore", { candidate_id: "c" })).toEqual({ ok: true, value: null })
    expect(yes.asked).toEqual(["Undo the restore and go back to your records from before?\n\nCopying pauses while it does."])
    expect(yes.calls).toEqual(["rollback:c"])
  })
})

describe("setAgentAccess", () => {
  it.each([
    ["off", "Turn off agent access?"],
    ["read_pause", "Allow agents to read and pause?"],
    ["propose", "Allow agents to read, pause, and ask for approval?"],
  ] as const)("asks before %s, naming what it allows", async (access, heading) => {
    const h = harness(true)
    expect(await h.api.act("setAgentAccess", { access })).toMatchObject({ ok: true, value: { access } })
    expect(h.asked[0]!.split("\n\n")[0]).toBe(heading)
    expect(h.calls).toEqual([`agents:${access}`])
  })

  it("changes nothing when the owner says no", async () => {
    const h = harness(false)
    expect(await h.api.act("setAgentAccess", { access: "propose" })).toMatchObject({ cancelled: true })
    expect(h.calls).toEqual([])
  })

  it("refuses a level that is not one of the three, without asking", async () => {
    const h = harness(true)
    expect(await h.api.act("setAgentAccess", { access: "everything" })).toMatchObject({ ok: false })
    expect(h.asked).toEqual([])
    expect(h.calls).toEqual([])
  })

  it("reads the socket's state", async () => {
    expect(await harness(true).api.read("getAgentAccess", undefined)).toEqual({ ok: true, value: { access: "propose", listening: true, problem: null } })
  })
})

describe("fill alerts", () => {
  it("are on until turned off, and stay as chosen", async () => {
    const h = harness(true)
    expect(await h.api.read("getFillAlerts", undefined)).toEqual({ ok: true, value: true })
    expect(await h.api.act("setFillAlerts", { on: false })).toEqual({ ok: true, value: false })
    expect(await h.api.read("getFillAlerts", undefined)).toEqual({ ok: true, value: false })
    expect(new Prefs(h.dir).get("fill_alerts")).toBe(false)
  })
})
