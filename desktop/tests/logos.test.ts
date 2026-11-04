import { existsSync, mkdtempSync, readFileSync, rmSync, utimesSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { LogoCache, logoUrl } from "../electron/main/logos"

// A real 1x1 PNG.
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==", "base64")
const reply = (ok: boolean, bytes: Buffer = PNG) => ({ ok, arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length) as ArrayBuffer })

let dir: string
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "logos-"))
})
afterEach(() => rmSync(dir, { recursive: true, force: true }))

describe("LogoCache", () => {
  it("fetches a ticker's logo once and serves it from disk after", async () => {
    const fetchLogo = vi.fn(async () => reply(true))
    const cache = new LogoCache(dir, fetchLogo)
    expect(await cache.logo("GFS")).toEqual(PNG)
    expect(await cache.logo("GFS")).toEqual(PNG)
    expect(fetchLogo).toHaveBeenCalledTimes(1)
    expect(readFileSync(join(dir, "GFS.png"))).toEqual(PNG)
  })

  it("sends nothing but the ticker", async () => {
    const fetchLogo = vi.fn(async (_url: string) => reply(true))
    await new LogoCache(dir, fetchLogo).logo("BRK.B")
    expect(fetchLogo.mock.calls).toEqual([["https://assets.parqet.com/logos/symbol/BRK.B?format=png"]])
    expect(logoUrl("F")).toBe("https://assets.parqet.com/logos/symbol/F?format=png")
  })

  it("answers a miss with nothing, and asks again no sooner than a day later", async () => {
    let now = Date.parse("2026-11-04T12:00:00Z")
    const fetchLogo = vi.fn(async () => reply(false))
    const cache = new LogoCache(dir, fetchLogo, () => now)
    expect(await cache.logo("ZZZZ")).toBeNull()
    now += 23 * 3600_000
    expect(await cache.logo("ZZZZ")).toBeNull()
    expect(fetchLogo).toHaveBeenCalledTimes(1)
    now += 2 * 3600_000
    fetchLogo.mockImplementation(async () => reply(true))
    expect(await cache.logo("ZZZZ")).toEqual(PNG)
    expect(fetchLogo).toHaveBeenCalledTimes(2)
  })

  it("treats an offline fetch and a body that is not a PNG as a miss, never a stored file", async () => {
    const offline = new LogoCache(dir, async () => Promise.reject(new Error("offline")))
    expect(await offline.logo("AAPL")).toBeNull()
    const page = new LogoCache(dir, async () => reply(true, Buffer.from("<html>login</html>")))
    expect(await page.logo("MSFT")).toBeNull()
    expect(existsSync(join(dir, "AAPL.png")) || existsSync(join(dir, "MSFT.png"))).toBe(false)
  })

  it("never builds a path or URL from something that is not a ticker", async () => {
    const fetchLogo = vi.fn(async () => reply(true))
    const cache = new LogoCache(dir, fetchLogo)
    for (const bad of ["../x", "aapl", "BTC/USD", "", "A".repeat(11)]) expect(await cache.logo(bad)).toBeNull()
    expect(fetchLogo).not.toHaveBeenCalled()
  })

  it("asks once for two requests at the same moment", async () => {
    const fetchLogo = vi.fn(async () => reply(true))
    const cache = new LogoCache(dir, fetchLogo)
    await Promise.all([cache.logo("SOFI"), cache.logo("SOFI")])
    expect(fetchLogo).toHaveBeenCalledTimes(1)
  })

  it("answers a ct-logo:// request with the PNG, or 404 for the page's letter tile", async () => {
    const cache = new LogoCache(dir, async (url) => reply(url.includes("/F?")))
    const hit = await cache.respond("ct-logo://f")
    expect([hit.status, hit.headers.get("content-type")]).toEqual([200, "image/png"])
    expect((await cache.respond("ct-logo://zzzz")).status).toBe(404)
  })

  it("keeps an old miss's age from the file, so a restart does not forget it", async () => {
    const first = new LogoCache(dir, async () => reply(false))
    await first.logo("NOPE")
    const old = new Date(Date.now() - 25 * 3600_000)
    utimesSync(join(dir, "NOPE.miss"), old, old)
    const fetchLogo = vi.fn(async () => reply(false))
    await new LogoCache(dir, fetchLogo).logo("NOPE")
    expect(fetchLogo).toHaveBeenCalledTimes(1)
  })
})
