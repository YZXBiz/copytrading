import { appendFileSync, mkdirSync, renameSync, statSync } from "node:fs"
import { dirname } from "node:path"

/** The engine's stderr keeps its last 256 KB in `engine.log` and the 256 KB before that in `engine.log.1`. */
export const MAX_LOG_BYTES = 256 * 1024

/**
 * Appends what the engine wrote to stderr (its own log lines and its crash text, which already leave keys out), starting a
 * new file when this one would pass `maxBytes`. A log that cannot be written never stops the engine.
 */
export function appendEngineLog(file: string, text: string | Buffer, maxBytes = MAX_LOG_BYTES): void {
  try {
    mkdirSync(dirname(file), { recursive: true, mode: 0o700 })
    let size = 0
    try {
      size = statSync(file).size
    } catch {} // no file yet
    if (size > 0 && size + Buffer.byteLength(text) > maxBytes) renameSync(file, `${file}.1`)
    appendFileSync(file, text, { mode: 0o600 })
  } catch {}
}
