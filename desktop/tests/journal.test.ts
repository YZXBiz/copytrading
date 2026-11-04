import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { parseEntry, readJournal } from "../electron/main/journal"

const dirs: string[] = []
afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })))
const journalDir = () => {
  const dir = mkdtempSync(join(tmpdir(), "journal-"))
  dirs.push(dir)
  return dir
}

const trading = (n: number, extra: Record<string, unknown> = {}) =>
  JSON.stringify({ kind: "trading", at: `2026-11-03T14:00:0${n}.123456+00:00`, operation: "workflow", outcome: "returned", created_at_ns: n, ...extra })

describe("parseEntry", () => {
  it("names a trading record by its operation, and how it ended by its ledger event first", () => {
    const entry = parseEntry(trading(1, { operation: "execution.ledger_event", ledger_event: "order_prepared", symbol: "F", qty: "10" }))!
    expect(entry).toMatchObject({ kind: "trading", name: "execution.ledger_event", outcome: "order_prepared", payload_json: null })
    expect(entry.fields).toEqual([
      { name: "ledger_event", value: "order_prepared" },
      { name: "operation", value: "execution.ledger_event" },
      { name: "outcome", value: "returned" },
      { name: "qty", value: "10" },
      { name: "symbol", value: "F" },
    ])
  })

  it("reads a captured payload as indented JSON with sorted keys, leaving it out of the fields", () => {
    const entry = parseEntry(JSON.stringify({ kind: "payload", at: "2026-11-03T14:00:00+00:00", capture_kind: "model_request", capture_status: "complete", payload: { b: 1, a: { d: [], c: true } } }))!
    expect(entry.name).toBe("model_request")
    expect(entry.fields.map((f) => f.name)).toEqual(["capture_kind", "capture_status"])
    expect(entry.payload_json).toBe('{\n  "a": {\n    "c": true,\n    "d": []\n  },\n  "b": 1\n}')
  })

  it("marks a payload whose bytes were not text, and shows none of it", () => {
    const entry = parseEntry(JSON.stringify({ kind: "payload", at: "2026-11-03T14:00:00+00:00", payload: { body: "ab�cd" } }))!
    expect(entry).toMatchObject({ payload_unreadable: true, payload_json: null })
  })

  it("skips a line that is not a record", () => {
    for (const line of ["", "not json", "[]", "{}", JSON.stringify({ kind: "other", at: "2026-11-03T14:00:00Z" }), JSON.stringify({ kind: "stage", at: "never" })]) {
      expect(parseEntry(line)).toBeNull()
    }
  })
})

describe("readJournal", () => {
  it("returns the newest entries first across the active file and its rotations, and counts every byte", () => {
    const dir = journalDir()
    const old = `${trading(1)}\n${trading(2)}\n`
    const fresh = `${trading(3)}\njunk\n${trading(4)}\n`
    writeFileSync(join(dir, "diagnostics.jsonl.1"), old)
    writeFileSync(join(dir, "diagnostics.jsonl"), fresh)
    const page = readJournal(dir)
    expect(page.entries.map((e) => e.at.slice(18, 19))).toEqual(["4", "3", "2", "1"])
    expect(page.bytes).toBe(Buffer.byteLength(old) + Buffer.byteLength(fresh))
  })

  it("stops at the limit", () => {
    const dir = journalDir()
    writeFileSync(join(dir, "diagnostics.jsonl"), [1, 2, 3].map((n) => trading(n)).join("\n"))
    expect(readJournal(dir, 2).entries).toHaveLength(2)
  })

  it("is empty, not an error, when nothing has been logged", () => {
    expect(readJournal(journalDir())).toEqual({ entries: [], bytes: 0 })
  })
})
