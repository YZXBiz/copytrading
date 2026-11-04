import { describe, expect, it } from "vitest"
import type { AccountOverview, TradingStatus } from "../../../shared/contract"
import { accountCopying, badgeVariant, isWarning, resumeBlocked } from "./copying"

const account = (over: Partial<AccountOverview> = {}): AccountOverview => ({
  account_id: "a",
  environment: "paper",
  entry_permission: "enabled",
  total_exposure_usd: null,
  positions: [],
  pending_orders: 0,
  balance: null,
  active_configuration: true,
  readiness: "enabled",
  ...over,
})
const status = (state: TradingStatus["state"], error_code: string | null = null): TradingStatus => ({
  state,
  configured_accounts: 1,
  active_accounts: 1,
  source_connected: true,
  model_ready: true,
  error_code,
})

describe("accountCopying", () => {
  it("copies when enabled and ready", () => {
    expect(accountCopying(account(), status("running"))).toEqual({ word: "copying", detail: null, warns: true })
  })

  it("is not started for an account outside the running setup", () => {
    expect(accountCopying(account({ active_configuration: false }), status("running")).word).toBe("notStarted")
    expect(accountCopying(account({ active_configuration: undefined }), null).word).toBe("notStarted")
  })

  it("is stopped, in words, when the engine could not keep the account", () => {
    expect(accountCopying(account({ readiness: "broker_keys_rejected" }), status("running"))).toMatchObject({
      word: "stopped",
      detail: "Alpaca didn't accept the API keys",
    })
    expect(accountCopying(account(), status("failed", "processing_unavailable"))).toMatchObject({
      word: "stopped",
      detail: "Copying stopped unexpectedly",
    })
  })

  it("is paused when copying as a whole is paused", () => {
    expect(accountCopying(account(), status("paused")).word).toBe("paused")
    expect(accountCopying(account({ readiness: "processing_stopped" }), status("running")).word).toBe("paused")
  })

  it("is sells only when the owner paused buys or a restart waits for them", () => {
    expect(accountCopying(account({ entry_permission: "paused" }), status("running"))).toMatchObject({
      word: "sellsOnly",
      detail: "You paused new buys; sells still go through",
    })
    expect(accountCopying(account({ entry_permission: "paused", readiness: "manual_resume_required" }), status("running")).word).toBe("sellsOnly")
    expect(accountCopying(account({ readiness: "manual_resume_required" }), status("running")).detail).toBe("Waiting for your Start Copying after a restart")
  })

  it("keeps copying with a quiet line before the market opens and a warning for anything else", () => {
    const quiet = accountCopying(account({ readiness: "enabled_waiting_for_session" }), status("running"))
    expect(quiet).toEqual({ word: "copying", detail: "Copies once the market opens", warns: false })
    expect(isWarning(quiet)).toBe(false)
    const warn = accountCopying(account({ readiness: "recovery_pending" }), status("running"))
    expect(isWarning(warn)).toBe(true)
    expect(badgeVariant(warn)).toBe("warning-light")
  })

  it("is not started when entries are off", () => {
    expect(accountCopying(account({ entry_permission: "disabled" }), status("running")).word).toBe("notStarted")
  })
})

describe("resumeBlocked", () => {
  it("says why an account cannot resume", () => {
    expect(resumeBlocked(account({ active_configuration: false }), status("running"))).toMatch(/Connections/)
    expect(resumeBlocked(account(), status("paused"))).toMatch(/Copying is off/)
    expect(resumeBlocked(account(), null)).toMatch(/Copying is off/)
  })

  it("lets a running account resume", () => {
    expect(resumeBlocked(account(), status("running"))).toBeNull()
    expect(resumeBlocked(account(), status("degraded"))).toBeNull()
  })
})
