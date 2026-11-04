import { copyFileSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import type { TradingConfiguration } from "../shared/contract"
import { SETUP_FILE, SetupFile } from "../electron/main/setup-file"

// tests/fixtures/trading-configuration.json is in the format TradingConfigurationStore.swift writes:
// compact JSON, camelCase envelope keys, an uppercase secretRevision, "\/" escapes, null and absent optionals.
const FIXTURE = join(__dirname, "fixtures", SETUP_FILE)
const original = JSON.parse(readFileSync(FIXTURE, "utf8"))
const dirs: string[] = []

function folder(copyFixture = true): string {
  const dir = mkdtempSync(join(tmpdir(), "setup-file-"))
  dirs.push(dir)
  if (copyFixture) copyFileSync(FIXTURE, join(dir, SETUP_FILE))
  return dir
}
const written = (dir: string) => JSON.parse(readFileSync(join(dir, SETUP_FILE), "utf8"))
const edited = (change: (file: typeof original) => void) => {
  const file = structuredClone(original)
  change(file)
  const dir = folder(false)
  writeFileSync(join(dir, SETUP_FILE), JSON.stringify(file))
  return new SetupFile(dir)
}

afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })))

describe("SetupFile", () => {
  it("loads the file the SwiftUI app wrote, unchanged", () => {
    const loaded = new SetupFile(folder()).load()!
    expect(loaded.configuration).toEqual(original.configuration)
    expect(loaded.revision).toBe(original.revision)
    expect(loaded.secretRevision).toBe(original.secretRevision)
    expect(loaded.pending_activation).toBeNull()
  })

  it("is empty when there is no file yet", () => {
    expect(new SetupFile(folder(false)).load()).toBeNull()
  })

  it("saves the same setup back in the same format, with a new key revision", () => {
    const dir = folder()
    const file = new SetupFile(dir)
    const loaded = file.load()!
    const secretRevision = file.save(loaded.configuration, loaded.revision)
    const saved = written(dir)
    expect(Object.keys(saved)).toEqual(["version", "configuration", "revision", "secretRevision"])
    expect(saved).toEqual({ ...original, secretRevision })
    expect(secretRevision).toMatch(/^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$/)
    expect(secretRevision).not.toBe(original.secretRevision)
    expect(statSync(join(dir, SETUP_FILE)).mode & 0o777).toBe(0o600)
  })

  it("keeps a null repeat window null and an absent author and base URL absent", () => {
    const dir = folder()
    const file = new SetupFile(dir)
    const loaded = file.load()!
    file.save(loaded.configuration, loaded.revision)
    const config: TradingConfiguration = written(dir).configuration
    expect(config.routes[0]).not.toHaveProperty("author_id")
    expect(config.routes[0]!.repeat_window_minutes).toBeNull()
    expect(config.provider).not.toHaveProperty("base_url")
    expect(config.notification).not.toHaveProperty("chat_id")
  })

  it("saves changed account limits under a new revision and keeps the keys' revision", () => {
    const dir = folder()
    const file = new SetupFile(dir)
    const config = structuredClone(original.configuration) as TradingConfiguration
    config.accounts[0]!.policy.max_order_usd = "250"
    const revision = "a".repeat(64)
    file.saveLimits(config, revision)
    const saved = written(dir)
    expect(saved.revision).toBe(revision)
    expect(saved.secretRevision).toBe(original.secretRevision)
    expect(saved.configuration.accounts[0].policy.max_order_usd).toBe("250")
  })

  it("refuses a limits save that changes anything but limits", () => {
    const file = new SetupFile(folder())
    const config = structuredClone(original.configuration) as TradingConfiguration
    config.routes[0]!.connections[0]!.full_position_usd = "9999"
    expect(() => file.saveLimits(config, "a".repeat(64))).toThrow(/Only account limits/)
  })

  it("loads the last confirmed setup while a start is unconfirmed, and refuses to save over it", () => {
    const previous = { configuration: original.configuration, revision: "b".repeat(64), secretRevision: "11111111-2222-3333-4444-555555555555" }
    const file = edited((f) => {
      f.pendingActivation = { activationID: "9d3f2c1a-0000-4000-8000-000000000001", candidateRevision: f.revision, previous }
    })
    const loaded = file.load()!
    expect(loaded.revision).toBe("b".repeat(64))
    expect(loaded.pending_activation).toEqual({ activation_id: "9d3f2c1a-0000-4000-8000-000000000001", candidate_revision: original.revision })
    expect(() => file.save(loaded.configuration, "c".repeat(64))).toThrow(/waiting/)
  })

  it("stages a start with the setup before it, and settles it either way", () => {
    const id = "9d3f2c1a-0000-4000-8000-000000000001"
    const dir = folder()
    const file = new SetupFile(dir)
    const loaded = file.load()!
    file.save(loaded.configuration, "a".repeat(64))
    file.stage(id)
    expect(written(dir).pendingActivation).toMatchObject({ activationID: id, candidateRevision: "a".repeat(64), previous: { revision: original.revision } })
    expect(file.pending()).toEqual({ activation_id: id, candidate_revision: "a".repeat(64) })
    expect(() => file.stage(id)).toThrow(/waiting/)
    expect(() => file.finalize("other")).toThrow(/not this one/)
    expect(file.rollback(id)).toBe(original.secretRevision)
    expect(written(dir)).toEqual(original)
    file.save(loaded.configuration, "a".repeat(64))
    file.stage(id)
    file.finalize(id)
    expect(Object.keys(written(dir))).toEqual(["version", "configuration", "revision", "secretRevision"])
    expect(written(dir).revision).toBe("a".repeat(64))
  })

  it("refuses to stage a start with an id the engine would not take", () => {
    expect(() => new SetupFile(folder()).stage("a")).toThrow(/valid id/)
    expect(() => new SetupFile(folder(false)).stage("9d3f2c1a-0000-4000-8000-000000000001")).toThrow(/no saved setup/)
  })

  it("removes the file when a first start does not take", () => {
    const id = "9d3f2c1a-0000-4000-8000-000000000001"
    const dir = folder(false)
    const file = new SetupFile(dir)
    file.save(original.configuration, original.revision)
    file.stage(id)
    expect(file.rollback(id)).toBeNull()
    expect(file.load()).toBeNull()
  })

  it("reports a setup from an earlier version instead of rewriting it", () => {
    const file = edited((f) => (f.configuration.version = 9))
    expect(() => file.load()).toThrow(/earlier version \(9\)/)
  })

  it.each([
    ["an envelope version other than 1", (f: typeof original) => (f.version = 2)],
    ["a revision that is not 64 lowercase hex", (f: typeof original) => (f.revision = "ABC")],
    ["a pending start for another revision", (f: typeof original) => (f.pendingActivation = { activationID: "x", candidateRevision: "d".repeat(64) })],
  ])("refuses a file with %s", (_name, change) => {
    expect(() => edited(change).load()).toThrow(/not a valid file/)
  })

  it("refuses a file that is not regular, such as a link to somewhere else", () => {
    const dir = folder(false)
    symlinkSync(FIXTURE, join(dir, SETUP_FILE))
    expect(() => new SetupFile(dir).load()).toThrow(/not a valid file/)
  })
})
