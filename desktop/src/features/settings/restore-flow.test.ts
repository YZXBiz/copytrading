import { describe, expect, it } from "vitest"
import type { Result, RestoreResult } from "../../../shared/contract"
import { blockersText, restore } from "./restore-flow"

const acts = (result: Result<RestoreResult>) => ({ activateRestore: async () => result })

describe("restore", () => {
  it("is done when main restored", async () => {
    expect(await restore(acts({ ok: true, value: { status: "restored" } }), { staging_id: "s" })).toEqual({ status: "done" })
  })

  it("passes the target on, a previewed backup or a half-done restore", async () => {
    const sent: unknown[] = []
    const fake = { activateRestore: async (p: unknown) => (sent.push(p), { ok: true, value: { status: "restored" } } as Result<RestoreResult>) }
    await restore(fake, { staging_id: "s" })
    await restore(fake, { candidate_id: "c" })
    expect(sent).toEqual([{ staging_id: "s" }, { candidate_id: "c" }])
  })

  it("is blocked, with the blockers, when the broker does not match", async () => {
    expect(await restore(acts({ ok: true, value: { status: "blocked", blockers: ["broker_state_mismatch"] } }), { candidate_id: "c" })).toEqual({
      status: "blocked",
      blockers: ["broker_state_mismatch"],
    })
  })

  it("reports a refusal in main's words, and a Cancel as cancelled", async () => {
    expect(await restore(acts({ ok: false, error: "Your data changed while restoring, so nothing was restored. Try again." }), { staging_id: "s" })).toEqual({
      status: "failed",
      error: "Your data changed while restoring, so nothing was restored. Try again.",
    })
    expect(await restore(acts({ ok: false, error: "Cancelled.", cancelled: true }), { staging_id: "s" })).toEqual({ status: "cancelled" })
  })
})

describe("blockersText", () => {
  it("puts each refusal in words", () => {
    expect(blockersText(["broker_state_mismatch", "account_outbox_pending"])).toBe(
      "Before it can restore: Alpaca's orders or holdings changed since the backup, a notification in the backup was never sent",
    )
  })
})
