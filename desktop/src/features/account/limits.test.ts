import { describe, expect, it } from "vitest"
import type { AccountPolicy, TradingConfiguration } from "../../../shared/contract"
import { draftFromPolicy, draftNumber, numberDraft, limitErrors, limitsChanged, policyFromDraft, setFlag, withLimits } from "./limits"

const policy: AccountPolicy = {
  max_order_usd: "100",
  max_symbol_usd: "600",
  max_total_usd: "2500",
  daily_loss_cap_usd: "250",
  max_entries_per_day: 30,
  max_signal_age_seconds: 600,
  order_timeout_seconds: 60,
  poll_seconds: 2,
  extended_hours: true,
  overnight: false,
  copy_exits: true,
  approve_orders: false,
  max_above_signal_pct: "0",
  max_below_signal_pct: "1",
  recovery_preference: "manual",
}

describe("limits draft", () => {
  it("round-trips a policy unchanged, keeping types the engine takes", () => {
    const draft = draftFromPolicy(policy)
    expect(draft.max_entries_per_day).toBe("30")
    expect(policyFromDraft(draft, policy)).toEqual(policy)
    expect(limitsChanged(draft, policy)).toBe(false)
  })

  it("sends dollars as strings and counts as integers, and keeps what it does not edit", () => {
    const next = policyFromDraft({ ...draftFromPolicy(policy), max_order_usd: " 250.50 ", max_entries_per_day: "12" }, policy)
    expect(next.max_order_usd).toBe("250.50")
    expect(next.max_entries_per_day).toBe(12)
    expect(next.poll_seconds).toBe(2)
  })

  it("does not call 100.0 a change from 100", () => {
    expect(limitsChanged({ ...draftFromPolicy(policy), max_order_usd: "100.0" }, policy)).toBe(false)
    expect(limitsChanged({ ...draftFromPolicy(policy), max_order_usd: "101" }, policy)).toBe(true)
    expect(limitsChanged({ ...draftFromPolicy(policy), recovery_preference: "automatic" }, policy)).toBe(true)
  })
})

describe("overnight needs extended hours", () => {
  it("ends overnight when extended hours go off, and starts them when overnight goes on", () => {
    const overnight = { ...draftFromPolicy(policy), overnight: true }
    expect(setFlag(overnight, "extended_hours", false)).toMatchObject({ extended_hours: false, overnight: false })
    expect(setFlag({ ...draftFromPolicy(policy), extended_hours: false }, "overnight", true)).toMatchObject({ extended_hours: true, overnight: true })
  })
})

describe("limitErrors", () => {
  it("accepts the saved limits", () => {
    expect(limitErrors(draftFromPolicy(policy))).toEqual({})
  })

  it("names each field that cannot be saved", () => {
    const errors = limitErrors({ ...draftFromPolicy(policy), max_order_usd: "abc", max_symbol_usd: "0", max_above_signal_pct: "-1", max_entries_per_day: "2.5", order_timeout_seconds: "0" })
    expect(errors).toEqual({
      max_order_usd: "Enter a number, like 250.",
      max_symbol_usd: "Must be more than 0.",
      max_above_signal_pct: "Enter a number, like 250.",
      max_entries_per_day: "Enter a whole number, 1 or more.",
      order_timeout_seconds: "Enter a whole number, 1 or more.",
    })
  })

  it("lets a percent be 0", () => {
    expect(limitErrors({ ...draftFromPolicy(policy), max_below_signal_pct: "0" })).toEqual({})
  })
})

describe("withLimits", () => {
  it("replaces only the named account's policy", () => {
    const config = { accounts: [{ id: "a", environment: "paper", policy }, { id: "b", environment: "paper", policy }], routes: [] } as unknown as TradingConfiguration
    const next = withLimits(config, "b", { ...policy, max_order_usd: "5" })
    expect(next.accounts[0]!.policy.max_order_usd).toBe("100")
    expect(next.accounts[1]!.policy.max_order_usd).toBe("5")
    expect(config.accounts[1]!.policy.max_order_usd).toBe("100")
  })
})

describe("stepper numbers", () => {
  it("reads a draft as a number, and nothing as null", () => {
    expect(draftNumber("250.50")).toBe(250.5)
    expect(draftNumber("")).toBeNull()
    expect(draftNumber("12abc")).toBeNull()
  })
  it("writes a step without float noise", () => {
    expect(numberDraft(0.1 + 0.2)).toBe("0.3")
    expect(numberDraft(260)).toBe("260")
  })
  it("writes a cleared field as empty, so the field's own check refuses it", () => {
    expect(numberDraft(null)).toBe("")
    expect(limitErrors({ ...draftFromPolicy(policy), max_order_usd: numberDraft(null) }).max_order_usd).toBeDefined()
  })
})
