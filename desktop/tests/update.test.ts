import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { describe, expect, it, vi } from "vitest"
import type { Result, TradingConfiguration } from "../shared/contract"
import { ResumeMarker, resumable, resumeCopying } from "../electron/main/resume"
import { RELEASES_URL, type UpdaterLike, Updates, copyingNote } from "../electron/main/update"

function setup(found: { isUpdateAvailable: boolean; updateInfo: { version: string } } | null, options: { accept?: boolean; copying?: boolean; downloadFails?: string } = {}) {
  const events: string[] = []
  const updater: UpdaterLike = {
    checkForUpdates: async () => found,
    downloadUpdate: async () => {
      events.push("download")
      if (options.downloadFails) throw new Error(options.downloadFails)
    },
    quitAndInstall: () => events.push("install"),
  }
  const told: string[] = []
  const offers: (string | null)[] = []
  const updates = new Updates(
    updater,
    {
      offer: async (_version, note) => {
        offers.push(note)
        return options.accept ?? true
      },
      tell: (message) => told.push(message),
    },
    async () => options.copying ?? false,
    (on) => events.push(on ? "remember" : "forget"),
  )
  return { updates, events, told, offers }
}
const NEW = { isUpdateAvailable: true, updateInfo: { version: "0.2.0-alpha.1" } }

describe("Updates", () => {
  it("downloads and installs once the owner agrees; with copying off it remembers nothing", async () => {
    const { updates, events } = setup(NEW)
    await updates.check()
    expect(events).toEqual(["download", "forget", "install"])
  })

  it("remembers running copying before it relaunches, and says what the update does to it", async () => {
    const { updates, events, offers } = setup(NEW, { copying: true })
    await updates.check()
    expect(events).toEqual(["download", "remember", "install"])
    expect(offers).toEqual([copyingNote(true)])
  })

  it("says nothing about copying when it is off", () => {
    expect(copyingNote(false)).toBeNull()
  })

  it("does nothing when the owner says Later, and does not ask again for that version", async () => {
    const { updates, events, offers } = setup(NEW, { accept: false })
    await updates.check()
    await updates.check()
    expect(events).toEqual([])
    expect(offers).toHaveLength(1)
    await updates.check(true)
    expect(offers).toHaveLength(2)
  })

  it("is quiet when there is nothing new, unless the owner asked", async () => {
    const { updates, told } = setup({ isUpdateAvailable: false, updateInfo: { version: "0.1.0" } })
    await updates.check()
    expect(told).toEqual([])
    await updates.check(true)
    expect(told).toEqual(["CopyTrading is up to date."])
  })

  it("stays running, forgets the resume, and points to the download when the install fails", async () => {
    const { updates, events, told } = setup(NEW, { copying: true, downloadFails: "code signature did not pass validation" })
    await updates.check()
    expect(events).toEqual(["download", "forget"])
    expect(told[0]).toContain("0.2.0-alpha.1 could not be installed: code signature did not pass validation")
    expect(told[0]).toContain(RELEASES_URL)
  })
})

describe("ResumeMarker", () => {
  it("is taken once", () => {
    const dir = mkdtempSync(join(tmpdir(), "marker-"))
    const marker = new ResumeMarker(join(dir, "resume-copying"))
    expect(marker.take()).toBe(false)
    marker.set()
    expect(marker.take()).toBe(true)
    expect(marker.take()).toBe(false)
    rmSync(dir, { recursive: true })
  })
})

const config = (...environments: string[]) => ({ accounts: environments.map((environment, i) => ({ id: `a${i}`, environment })) }) as unknown as TradingConfiguration

describe("resumeCopying", () => {
  it("only resumes a paper-only setup", () => {
    expect(resumable(config("paper", "paper"))).toBe(true)
    expect(resumable(config("paper", "live"))).toBe(false)
  })

  function fakeApi(state: string, validation: Result<unknown>, start: Result<unknown> = { ok: true, value: {} }) {
    const calls: string[] = []
    const api = {
      read: async () => ({ ok: true, value: { state } }) as Result<unknown>,
      act: async (name: string) => {
        calls.push(name)
        return name === "validateTrading" ? validation : start
      },
    }
    return { api, calls }
  }
  const passing: Result<unknown> = { ok: true, value: { report: { activatable: true }, activation_token: "token" } }
  const now = async () => {}

  it("validates, then starts", async () => {
    const { api, calls } = fakeApi("paused", passing)
    expect(await resumeCopying(api, () => ({ configuration: config("paper") }), now)).toBeNull()
    expect(calls).toEqual(["validateTrading", "startTrading"])
  })

  it("leaves copying alone when it already runs, or the setup has a live account", async () => {
    const running = fakeApi("running", passing)
    expect(await resumeCopying(running.api, () => ({ configuration: config("paper") }), now)).toBeNull()
    expect(running.calls).toEqual([])
    const live = fakeApi("paused", passing)
    expect(await resumeCopying(live.api, () => ({ configuration: config("live") }), now)).toMatch(/live account/)
    expect(live.calls).toEqual([])
  })

  it("tries again after a failed check, then says why it gave up", async () => {
    const failing: Result<unknown> = { ok: true, value: { report: { activatable: false }, activation_token: null } }
    const { api, calls } = fakeApi("paused", failing)
    const wait = vi.fn((_ms: number) => now())
    const why = await resumeCopying(api, () => ({ configuration: config("paper") }), wait, [0, 5, 5])
    expect(why).toMatch(/Connections shows what to fix/)
    expect(calls).toEqual(["validateTrading", "validateTrading", "validateTrading"])
    expect(wait.mock.calls.map(([ms]) => ms)).toEqual([0, 5, 5])
  })
})
