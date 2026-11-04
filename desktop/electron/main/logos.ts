import { existsSync, mkdirSync, readFileSync, statSync, utimesSync, writeFileSync } from "node:fs"
import { join } from "node:path"

// Company logos for the page, served as ct-logo://<SYMBOL>. The first ask for a ticker fetches its PNG from Parqet and
// keeps it under <dir>/<SYMBOL>.png; a ticker Parqet does not have is remembered as a miss and asked for again at most
// once a day. The only thing that leaves the Mac is the ticker in the URL: no key, header, cookie or account.

export const LOGO_SCHEME = "ct-logo"
const SYMBOL = /^[A-Z][A-Z0-9.]{0,9}$/
const MAX_BYTES = 512 * 1024
const MISS_FOR_MS = 24 * 60 * 60 * 1000
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

export const logoUrl = (symbol: string) => `https://assets.parqet.com/logos/symbol/${encodeURIComponent(symbol)}?format=png`

type Fetch = (url: string) => Promise<{ ok: boolean; arrayBuffer: () => Promise<ArrayBuffer> }>

export class LogoCache {
  private readonly inflight = new Map<string, Promise<Buffer | null>>()

  constructor(
    private readonly dir: string,
    private readonly fetchLogo: Fetch = (url) => fetch(url, { redirect: "error", credentials: "omit", signal: AbortSignal.timeout(5000) }),
    private readonly now: () => number = Date.now,
  ) {}

  /** The PNG for a ticker: from disk, else fetched once; null for a miss. */
  async logo(symbol: string): Promise<Buffer | null> {
    if (!SYMBOL.test(symbol)) return null
    const file = join(this.dir, `${symbol}.png`)
    if (existsSync(file)) return readFileSync(file)
    const miss = join(this.dir, `${symbol}.miss`)
    if (existsSync(miss) && this.now() - statSync(miss).mtimeMs < MISS_FOR_MS) return null
    let ask = this.inflight.get(symbol)
    if (!ask) {
      ask = this.download(symbol, file, miss).finally(() => this.inflight.delete(symbol))
      this.inflight.set(symbol, ask)
    }
    return ask
  }

  private async download(symbol: string, file: string, miss: string): Promise<Buffer | null> {
    mkdirSync(this.dir, { recursive: true })
    try {
      const reply = await this.fetchLogo(logoUrl(symbol))
      const bytes = reply.ok ? Buffer.from(await reply.arrayBuffer()) : null
      if (bytes && bytes.length <= MAX_BYTES && bytes.subarray(0, 8).equals(PNG)) {
        writeFileSync(file, bytes)
        return bytes
      }
    } catch {
      // Offline or slow: a miss for today, like any other.
    }
    writeFileSync(miss, "")
    utimesSync(miss, new Date(this.now()), new Date(this.now()))
    return null
  }

  /** The answer to a ct-logo://<SYMBOL> request: the PNG, or 404 so the page shows its letter tile. */
  async respond(url: string): Promise<Response> {
    const bytes = await this.logo(new URL(url).hostname.toUpperCase())
    if (!bytes) return new Response(null, { status: 404 })
    return new Response(new Uint8Array(bytes), { headers: { "content-type": "image/png", "x-content-type-options": "nosniff", "cache-control": "private, max-age=86400" } })
  }
}
