import { copyFileSync, mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { type Engine, createApi } from "../electron/main/api"
import { AccountReaders } from "../electron/main/readers"
import { SecretStore } from "../electron/main/secrets"
import { SETUP_FILE, SetupFile } from "../electron/main/setup-file"
import { unusedBackground } from "./background-stubs"

const dirs: string[] = []
afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })))
const cipher = { encrypt: (text: string) => Buffer.from(text).reverse(), decrypt: (data: Buffer) => Buffer.from(data).reverse().toString() }

// The fixture setup holds zhap-account-2 and zhap-account-3, both paper.
const KEY = "PKSENTINELKEY2"
const SECRET = "SENTINELSECRET2-aaaaaaaaaaaaaaaa"

function harness(options: { failing?: boolean } = {}) {
  const attached: { accounts: { account_id: string; environment: string; key: string; secret: string }[] }[] = []
  const sent: string[] = []
  const engine: Engine = {
    request: async (op, params = {}) => {
      sent.push(op)
      if (op === "attach_account_readers") {
        if (options.failing) throw new Error("The engine is starting.")
        attached.push(params as (typeof attached)[number])
      }
      return { type: "ok", trading: { state: "paused" } }
    },
  }
  const dir = mkdtempSync(join(tmpdir(), "readers-"))
  dirs.push(dir)
  copyFileSync(join(__dirname, "fixtures", SETUP_FILE), join(dir, SETUP_FILE))
  const secrets = new SecretStore(join(dir, "secrets.bin"), cipher)
  const setup = new SetupFile(dir)
  const readers = new AccountReaders((op, params) => engine.request(op, params), setup, secrets)
  const api = createApi({ engine, setup, secrets, confirm: async () => true, ...unusedBackground(dir), readers })
  return { api, readers, secrets, attached, sent, setup }
}

const broker = (account_id: string, key = KEY, secret = SECRET) => ({ account_id, key, secret })

describe("AccountReaders", () => {
  it("sends each saved account's keys with its environment, and only that account's", async () => {
    const h = harness()
    h.secrets.merge({ brokers: [broker("zhap-account-2"), broker("removed-account")] })
    h.secrets.stage()
    await h.readers.attach()
    expect(h.attached).toEqual([{ accounts: [{ account_id: "zhap-account-2", environment: "paper", key: KEY, secret: SECRET }] }])
  })

  it("does not send keys the owner typed and has not saved with a start", async () => {
    const h = harness()
    h.secrets.merge({ brokers: [broker("zhap-account-2")] })
    await h.readers.attach()
    expect(h.attached).toEqual([{ accounts: [] }])
  })

  it("sends nothing for an account that has no key and secret yet", async () => {
    const h = harness()
    h.secrets.merge({ brokers: [broker("zhap-account-2", KEY, ""), broker("zhap-account-3", "", SECRET)] })
    h.secrets.stage()
    await h.readers.attach()
    expect(h.attached).toEqual([{ accounts: [] }])
  })

  it("does not send again while nothing changed, so the engine keeps its cached reads", async () => {
    const h = harness()
    h.secrets.merge({ brokers: [broker("zhap-account-2")] })
    h.secrets.stage()
    await h.readers.attach()
    await h.readers.attach()
    expect(h.attached).toHaveLength(1)
    h.secrets.merge({ brokers: [broker("zhap-account-2", "PKNEWKEY2222")] })
    h.secrets.stage()
    await h.readers.attach()
    expect(h.attached).toHaveLength(2)
  })

  it("sends again after the engine started, since a new engine holds no keys", async () => {
    const h = harness()
    h.secrets.merge({ brokers: [broker("zhap-account-2")] })
    h.secrets.stage()
    await h.readers.attach()
    await h.readers.attach(true)
    expect(h.attached).toHaveLength(2)
  })

  it("never throws when the engine does not answer, and tries again at the next change", async () => {
    const failing = harness({ failing: true })
    failing.secrets.merge({ brokers: [broker("zhap-account-2")] })
    failing.secrets.stage()
    await expect(failing.readers.attach()).resolves.toBeUndefined()
    await failing.readers.attach()
    expect(failing.sent.filter((op) => op === "attach_account_readers")).toHaveLength(2)
  })
})

describe("through the api", () => {
  it("attaches the keys after a setup is saved, and the page's reply never carries them", async () => {
    const h = harness()
    h.secrets.merge({ brokers: [broker("zhap-account-2")] })
    h.secrets.stage()
    const saved = h.setup.current()!
    const result = await h.api.act("saveSetup", { configuration: saved.configuration, revision: saved.revision })
    expect(result).toMatchObject({ ok: true })
    expect(h.attached).toHaveLength(1)
    expect(JSON.stringify(result)).not.toContain(KEY)
  })

  it("sends the keys again, without the account's, after they are forgotten", async () => {
    const h = harness()
    h.secrets.merge({ brokers: [broker("zhap-account-2")] })
    h.secrets.stage()
    await h.readers.attach()
    await h.api.act("forgetBroker", { account_id: "zhap-account-2" })
    expect(h.attached.at(-1)).toEqual({ accounts: [] })
  })

  it("does not attach for a read or an action that changes no key", async () => {
    const h = harness()
    h.secrets.merge({ brokers: [broker("zhap-account-2")] })
    await h.api.read("getStatus", undefined)
    await h.api.act("setSecrets", { discord_token: "x" })
    expect(h.sent).not.toContain("attach_account_readers")
  })
})
