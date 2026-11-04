import { describe, expect, it } from "vitest"
import type { TradingStatus } from "../../../shared/contract"
import { type Progress } from "./state"
import { canStartCopying, startStatus } from "./start-status"

const trading = (state: TradingStatus["state"]): TradingStatus => ({
  state,
  configured_accounts: 1,
  active_accounts: 0,
  source_connected: false,
  model_ready: false,
  error_code: null,
})
const progress = (done: Progress["done"], next: Progress["next"]): Progress => ({
  done,
  next,
  isReadyToCheck: ["discord", "interpreter", "account", "guru"].every((s) => done.has(s as never)),
})
const READY = progress(new Set(["discord", "interpreter", "account", "guru"]), "start")
const base = { start: { phase: "idle" } as const, progress: READY, trading: trading("paused"), isCopying: false, hasSaved: false, hasUnsaved: true }

describe("startStatus", () => {
  it("says what is under way", () => {
    expect(startStatus({ ...base, start: { phase: "checking" } }).text).toBe("Checking every connection…")
    expect(startStatus({ ...base, start: { phase: "starting" } }).tone).toBe("working")
    expect(startStatus({ ...base, start: { phase: "pending" } }).text).toBe("Starting your new setup…")
  })

  it("counts the checks that need attention, and says a message that is not one", () => {
    const report = { configuration_revision: "", activatable: false, cost_notice: "", checks: [{ state: "failed" }, { state: "ready" }, { state: "failed" }] }
    const failed = startStatus({ ...base, start: { phase: "failed", message: "x", report: report as never } })
    expect(failed).toMatchObject({ text: "2 checks need attention", detail: "Review them, then start again. Nothing was saved." })
    expect(startStatus({ ...base, start: { phase: "failed", message: "Enter your Discord token in Connections first.", report: null } })).toMatchObject({
      text: "Not started",
      detail: "Enter your Discord token in Connections first.",
    })
  })

  it("waits for the engine, and locks the form while copying runs", () => {
    expect(startStatus({ ...base, trading: null }).text).toBe("Waiting for the engine…")
    expect(startStatus({ ...base, trading: trading("running"), isCopying: true }).text).toBe("Copying is running")
  })

  it("counts the steps and points at the next while the setup is incomplete", () => {
    const some = progress(new Set(["discord", "interpreter"]), "account")
    expect(startStatus({ ...base, progress: some })).toMatchObject({ text: "2 of 5 steps done", detail: "Next: Add a broker account." })
    // A setup started before counts as its step, as the guide counts it.
    const withStart = progress(new Set(["discord", "start"]), "interpreter")
    expect(startStatus({ ...base, progress: withStart }).text).toBe("2 of 5 steps done")
  })

  it("offers to start a filled-in setup", () => {
    expect(startStatus(base).text).toBe("Ready to start")
    expect(startStatus({ ...base, hasSaved: true }).text).toBe("You have unsaved changes")
  })
})

describe("canStartCopying", () => {
  it("needs a filled-in setup, copying stopped, and nothing under way", () => {
    expect(canStartCopying(base)).toBe(true)
    expect(canStartCopying({ ...base, trading: trading("failed") })).toBe(true)
    expect(canStartCopying({ ...base, trading: trading("running") })).toBe(false)
    expect(canStartCopying({ ...base, trading: null })).toBe(false)
    expect(canStartCopying({ ...base, progress: progress(new Set(["discord"]), "interpreter") })).toBe(false)
    expect(canStartCopying({ ...base, start: { phase: "checking" } })).toBe(false)
  })
})
