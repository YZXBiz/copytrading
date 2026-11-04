import { describe, expect, it } from "vitest"
import type { Result } from "../../../shared/contract"
import { blockersText, finishRestore, restoreFromPreview } from "./restore-flow"

const ok = <T>(value: T): Result<T> => ({ ok: true, value })
const preflight = (over: object = {}) => ok({ candidate_id: "c1", eligible: true, checked_account_count: 1, blockers: [], completion_token: "tok", ...over })

type Fake = Parameters<typeof restoreFromPreview>[0] & { calls: string[] }

function acts(over: Partial<Record<string, unknown>> = {}): Fake {
  const calls: string[] = []
  return {
    calls,
    prepareRestoreCandidate: async () => (calls.push("prepare"), ok({ candidate_id: "c1" })),
    restorePreflight: async () => (calls.push("preflight"), preflight()),
    completeRestoreCandidate: async (p: object) => (calls.push(`complete:${JSON.stringify(p)}`), ok(null)),
    ...over,
  } as never
}

describe("finishRestore", () => {
  it("completes with the token the check returned", async () => {
    const a = acts()
    expect(await finishRestore(a, "c1")).toEqual({ status: "done" })
    expect(a.calls).toEqual(["preflight", 'complete:{"candidate_id":"c1","completion_token":"tok"}'])
  })

  it("stops with the blockers, and completes nothing, when the broker does not match", async () => {
    const a = acts({ restorePreflight: async () => preflight({ eligible: false, completion_token: null, blockers: ["broker_state_mismatch"] }) })
    expect(await finishRestore(a, "c1")).toEqual({ status: "blocked", blockers: ["broker_state_mismatch"] })
    expect(a.calls).toEqual([])
  })

  it("treats an eligible check with no token as blocked rather than guessing", async () => {
    const a = acts({ restorePreflight: async () => preflight({ completion_token: null }) })
    expect((await finishRestore(a, "c1")).status).toBe("blocked")
  })

  it("reports a refusal in the engine's words, and a Cancel as cancelled", async () => {
    expect(await finishRestore(acts({ restorePreflight: async () => ({ ok: false, error: "No keys are saved for X." }) }), "c1")).toEqual({ status: "failed", error: "No keys are saved for X." })
    expect(await finishRestore(acts({ completeRestoreCandidate: async () => ({ ok: false, error: "Cancelled.", cancelled: true }) }), "c1")).toEqual({ status: "cancelled" })
    expect(await finishRestore(acts({ completeRestoreCandidate: async () => ({ ok: false, error: "The engine did not accept the request." }) }), "c1")).toEqual({ status: "failed", error: "The engine did not accept the request." })
  })
})

describe("restoreFromPreview", () => {
  it("prepares, checks, then completes", async () => {
    const a = acts()
    expect(await restoreFromPreview(a, "stage")).toEqual({ status: "done" })
    expect(a.calls.slice(0, 2)).toEqual(["prepare", "preflight"])
  })
  it("goes no further when preparing fails", async () => {
    const a = acts({ prepareRestoreCandidate: async () => ({ ok: false, error: "Another restore is waiting." }) })
    expect(await restoreFromPreview(a, "stage")).toEqual({ status: "failed", error: "Another restore is waiting." })
    expect(a.calls).toEqual([])
  })
})

describe("blockersText", () => {
  it("puts each refusal in words", () => {
    expect(blockersText(["broker_state_mismatch", "account_outbox_pending"])).toBe(
      "Before it can restore: Alpaca's orders or holdings changed since the backup, a notification in the backup was never sent",
    )
  })
})
