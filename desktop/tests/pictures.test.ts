import { createHash } from "node:crypto"
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { PictureIndex, readPicture } from "../electron/main/pictures"

// A real 1x1 PNG.
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==", "base64")
const sha = (bytes: Buffer) => createHash("sha256").update(bytes).digest("hex")
const ID = "0123456789abcdef0123456789abcdef"

let dir: string
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "pictures-"))
})
afterEach(() => rmSync(dir, { recursive: true, force: true }))

/** Stores bytes where the engine does: <dir>/<sha[:2]>/<sha>. */
function store(bytes: Buffer, name = sha(bytes)): void {
  mkdirSync(join(dir, name.slice(0, 2)), { recursive: true })
  writeFileSync(join(dir, name.slice(0, 2), name), bytes)
}

describe("readPicture", () => {
  it("returns a file whose size and hash match the evidence", () => {
    store(PNG)
    expect(readPicture(dir, { sha256: sha(PNG), size: PNG.length })?.type).toBe("image/png")
  })

  it("refuses a file whose content does not hash to the recorded digest", () => {
    const tampered = Buffer.from(PNG)
    tampered[tampered.length - 1] ^= 0xff
    store(tampered, sha(PNG))
    expect(readPicture(dir, { sha256: sha(PNG), size: PNG.length })).toBeNull()
  })

  it("refuses a file of a different size than recorded, longer or shorter", () => {
    store(PNG)
    expect(readPicture(dir, { sha256: sha(PNG), size: PNG.length - 1 })).toBeNull()
    expect(readPicture(dir, { sha256: sha(PNG), size: PNG.length + 1 })).toBeNull()
  })

  it("refuses bytes that are not a raster picture, even with a matching hash", () => {
    const page = Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'><script>1</script></svg>")
    store(page)
    expect(readPicture(dir, { sha256: sha(page), size: page.length })).toBeNull()
  })

  it("refuses a link in place of the file", () => {
    store(PNG, "ff".repeat(32))
    const real = join(dir, "ff", "ff".repeat(32))
    mkdirSync(join(dir, sha(PNG).slice(0, 2)), { recursive: true })
    symlinkSync(real, join(dir, sha(PNG).slice(0, 2), sha(PNG)))
    expect(readPicture(dir, { sha256: sha(PNG), size: PNG.length })).toBeNull()
  })

  it("refuses a digest that is not 64 lowercase hex characters, so no path can be built from it", () => {
    expect(readPicture(dir, { sha256: "../../etc/passwd", size: 10 })).toBeNull()
    expect(readPicture(dir, { sha256: sha(PNG).toUpperCase(), size: PNG.length })).toBeNull()
  })

  it("refuses a size above the engine's cap or below one byte", () => {
    expect(readPicture(dir, { sha256: sha(PNG), size: 4 * 1024 * 1024 + 1 })).toBeNull()
    expect(readPicture(dir, { sha256: sha(PNG), size: 0 })).toBeNull()
  })
})

describe("PictureIndex", () => {
  const reply = (evidence: Record<string, unknown>) => ({ items: [{ source_event: { attachments: [evidence] } }] })
  const evidence = { evidence_id: ID, status: "available", sha256: sha(PNG), byte_size: PNG.length }

  it("serves an attachment the engine reported, found anywhere in a reply", async () => {
    store(PNG)
    const index = new PictureIndex()
    index.learn(reply(evidence))
    const response = index.respond(dir, `ct-picture://${ID}`)
    expect(response.status).toBe(200)
    expect(response.headers.get("content-type")).toBe("image/png")
    expect(Buffer.from(await response.arrayBuffer()).equals(PNG)).toBe(true)
  })

  it("answers 404 when the stored file does not match the evidence", () => {
    store(Buffer.from(PNG), sha(PNG))
    const index = new PictureIndex()
    index.learn(reply({ ...evidence, sha256: sha(Buffer.from("something else")) }))
    expect(index.respond(dir, `ct-picture://${ID}`).status).toBe(404)
  })

  it("answers 404 for an id the engine never reported or reported as not available", () => {
    store(PNG)
    const index = new PictureIndex()
    index.learn(reply({ ...evidence, status: "failed" }))
    expect(index.respond(dir, `ct-picture://${ID}`).status).toBe(404)
    expect(index.respond(dir, "ct-picture://ffffffffffffffffffffffffffffffff").status).toBe(404)
  })
})
