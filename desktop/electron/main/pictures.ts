import { createHash } from "node:crypto"
import { closeSync, constants, openSync, readSync } from "node:fs"
import { join } from "node:path"

// Pictures the engine captured with a post, served to the page as ct-picture://<evidence_id>. A file is
// returned only when its size and SHA-256 match what the engine recorded for that evidence (SourcePictures.swift).
// The record comes from the engine's own replies as they pass through main (`learn`), never from the page.

export const PICTURE_SCHEME = "ct-picture"
/** The engine's cap for one captured file. */
const MAX_BYTES = 4 * 1024 * 1024
const EVIDENCE_ID = /^[0-9a-f]{32}$/
const SHA256 = /^[0-9a-f]{64}$/

interface Evidence {
  sha256: string
  size: number
}

/** The type a picture's own bytes declare; anything that is not a plain raster picture is refused. */
function pictureType(bytes: Buffer): string | null {
  if (bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "image/png"
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg"
  if (bytes.subarray(0, 4).toString("latin1") === "GIF8") return "image/gif"
  if (bytes.subarray(0, 4).toString("latin1") === "RIFF" && bytes.subarray(8, 12).toString("latin1") === "WEBP") return "image/webp"
  return null
}

/** Reads `<attachments>/<sha[:2]>/<sha>` without following a link; null unless size and hash both match. */
export function readPicture(attachments: string, evidence: Evidence): { bytes: Buffer; type: string } | null {
  if (!SHA256.test(evidence.sha256) || !Number.isInteger(evidence.size) || evidence.size < 1 || evidence.size > MAX_BYTES) return null
  let fd: number
  try {
    fd = openSync(join(attachments, evidence.sha256.slice(0, 2), evidence.sha256), constants.O_RDONLY | constants.O_NOFOLLOW)
  } catch {
    return null
  }
  try {
    // One byte more than the recorded size: a longer file is a different file.
    const bytes = Buffer.alloc(evidence.size + 1)
    let read = 0
    while (read < bytes.length) {
      const n = readSync(fd, bytes, read, bytes.length - read, null)
      if (n === 0) break
      read += n
    }
    if (read !== evidence.size) return null
    const picture = bytes.subarray(0, evidence.size)
    const type = pictureType(picture)
    return type && createHash("sha256").update(picture).digest("hex") === evidence.sha256 ? { bytes: picture, type } : null
  } catch {
    return null
  } finally {
    closeSync(fd)
  }
}

/** The available attachments the engine has reported, by evidence id. */
export class PictureIndex {
  private readonly known = new Map<string, Evidence>()

  /** Notes every attachment in an engine reply, wherever it sits in it. */
  learn(value: unknown): void {
    if (Array.isArray(value)) return value.forEach((item) => this.learn(item))
    if (typeof value !== "object" || value === null) return
    const record = value as Record<string, unknown>
    const { evidence_id: id, sha256, byte_size: size, status } = record
    if (typeof id === "string" && EVIDENCE_ID.test(id) && status === "available" && typeof sha256 === "string" && typeof size === "number") {
      this.known.set(id, { sha256, size })
    }
    Object.values(record).forEach((item) => this.learn(item))
  }

  /** The answer to a ct-picture://<evidence_id> request. */
  respond(attachments: string, url: string): Response {
    const id = new URL(url).hostname
    const evidence = this.known.get(id)
    const picture = evidence && readPicture(attachments, evidence)
    if (!picture) return new Response(null, { status: 404 })
    return new Response(new Uint8Array(picture.bytes), {
      headers: { "content-type": picture.type, "x-content-type-options": "nosniff", "cache-control": "private, max-age=3600" },
    })
  }
}
