import { describe, expect, it } from "vitest"
import type { TradingStatus } from "../../../shared/contract"
import { type Progress } from "./state"
import { canApplyChanges, canStartCopying, startStatus } from "./start-status"

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
    expect(startStatus({ ...base, start: { phase: "pending", activationId: "x" } }).text).toBe("Starting your new setup…")
  })

  it("names the accounts a committed start left not buying, instead of saying all is well", () => {
    const running = { ...base, trading: trading("running"), isCopying: true, hasUnsaved: false }
    expect(startStatus({ ...running, start: { phase: "started", paused: [] } }).text).toBe("Copying is running")
    expect(startStatus({ ...running, start: { phase: "started", paused: ["a", "b"] } })).toMatchObject({
      text: "Started, but not buying everywhere",
      detail: "a and b are not buying yet. Resume them on the account page.",
      tone: "caution",
    })
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

  it("waits for the engine, and offers to apply a change while copying runs", () => {
    expect(startStatus({ ...base, trading: null }).text).toBe("Waiting for the engine…")
    const running = { ...base, trading: trading("running"), isCopying: true }
    expect(startStatus({ ...running, hasUnsaved: false }).text).toBe("Copying is running")
    expect(startStatus({ ...running, hasUnsaved: true })).toMatchObject({
      text: "You changed the setup",
      detail: "Apply changes to use it. Copying restarts in a few seconds, and any post sent meanwhile is still copied.",
    })
    expect(startStatus({ ...running, start: { phase: "applying" } }).text).toBe("Applying your changes…")
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

describe("canApplyChanges", () => {
  const copying = { start: { phase: "idle" } as const, progress: READY, isCopying: true, hasUnsaved: true }
  it("needs copying running on a saved setup, an edited and filled-in form, and nothing under way", () => {
    expect(canApplyChanges(copying)).toBe(true)
    expect(canApplyChanges({ ...copying, isCopying: false })).toBe(false)
    expect(canApplyChanges({ ...copying, hasUnsaved: false })).toBe(false)
    expect(canApplyChanges({ ...copying, progress: progress(new Set(["discord"]), "interpreter") })).toBe(false)
    // A second press while the first apply runs must not start another.
    expect(canApplyChanges({ ...copying, start: { phase: "applying" } })).toBe(false)
    expect(canApplyChanges({ ...copying, start: { phase: "pending", activationId: "x" } })).toBe(false)
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
