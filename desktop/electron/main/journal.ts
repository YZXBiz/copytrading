import { closeSync, existsSync, fstatSync, openSync, readSync, statSync } from "node:fs"
import { join } from "node:path"
import type { DiagnosticsEntry, DiagnosticsPage } from "../../shared/contract"

// The engine's private journal, read straight from disk as DiagnosticsJournal.swift does: the active file,
// then `.1` to `.7`, newest first. A file can reach gigabytes, so only its last TAIL_BYTES are read.

const FILE = "diagnostics.jsonl"
const ROTATIONS = 7
const TAIL_BYTES = 8 * 1024 * 1024
const DEFAULT_LIMIT = 2000
const HIDDEN = new Set(["kind", "at", "payload", "created_at_ns"])
const KINDS = new Set(["stage", "payload", "trading"])

const files = (dir: string) =>
  [FILE, ...Array.from({ length: ROTATIONS }, (_, i) => `${FILE}.${i + 1}`)].map((name) => join(dir, name)).filter((path) => existsSync(path))

/** The last `TAIL_BYTES` of a file as text; a cut first line is dropped, as it is not a whole record. */
function tail(path: string): string {
  const fd = openSync(path, "r")
  try {
    const size = fstatSync(fd).size
    const start = Math.max(0, size - TAIL_BYTES)
    const buffer = Buffer.alloc(size - start)
    readSync(fd, buffer, 0, buffer.length, start)
    const text = buffer.toString("utf8")
    return start > 0 ? text.slice(text.indexOf("\n") + 1) : text
  } finally {
    closeSync(fd)
  }
}

/** Objects with their keys in order, so the same payload always prints the same way. */
function sorted(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sorted)
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
        .map(([key, inner]) => [key, sorted(inner)]),
    )
  }
  return value
}

const text = (value: unknown): string => (typeof value === "string" ? value : JSON.stringify(sorted(value)))
const str = (value: unknown, fallback: string): string => (typeof value === "string" ? value : fallback)

/** One journal line shaped for reading; null for a line that is not a record. */
export function parseEntry(line: string): DiagnosticsEntry | null {
  let object: Record<string, unknown>
  try {
    const parsed: unknown = JSON.parse(line)
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
    object = parsed as Record<string, unknown>
  } catch {
    return null
  }
  const kind = object.kind
  const at = object.at
  if (typeof kind !== "string" || !KINDS.has(kind) || typeof at !== "string" || Number.isNaN(Date.parse(at))) return null
  const [name, outcome] =
    kind === "stage"
      ? [str(object.stage, "other"), str(object.outcome, "other")]
      : kind === "payload"
        ? [str(object.capture_kind, "other"), str(object.capture_status, "other")]
        : [str(object.operation, "other"), str(object.ledger_event ?? object.outcome, "other")]
  const body = (object.payload as { body?: unknown } | null | undefined)?.body
  // A reply of bytes that were not text was journaled with every bad byte replaced by U+FFFD.
  const unreadable = typeof body === "string" && body.includes("�")
  return {
    id: `${object.created_at_ns ?? at}-${line.length}-${name}-${outcome}`,
    kind: kind as DiagnosticsEntry["kind"],
    at,
    name,
    outcome,
    trace_id: typeof object.trace_id === "string" ? object.trace_id : null,
    workflow_id: typeof object.workflow_id === "string" ? object.workflow_id : null,
    fields: Object.entries(object)
      .filter(([key, value]) => !HIDDEN.has(key) && value !== null)
      .map(([key, value]) => ({ name: key, value: text(value) }))
      .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)),
    payload_json: object.payload == null || unreadable ? null : JSON.stringify(sorted(object.payload), null, 2),
    payload_unreadable: unreadable,
  }
}

/** The newest `limit` readable entries, newest first, and the bytes the journal holds. */
export function readJournal(dir: string, limit = DEFAULT_LIMIT): DiagnosticsPage {
  const entries: DiagnosticsEntry[] = []
  let bytes = 0
  for (const path of files(dir)) {
    bytes += statSync(path).size
    if (entries.length >= limit) continue
    const lines = tail(path).split("\n")
    for (let i = lines.length - 1; i >= 0 && entries.length < limit; i--) {
      const entry = lines[i] ? parseEntry(lines[i]!) : null
      if (entry) entries.push(entry)
    }
  }
  return { entries, bytes }
}
