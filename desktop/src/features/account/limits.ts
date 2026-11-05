import type { AccountPolicy, RecoveryPreference, TradingConfiguration } from "../../../shared/contract"
import { parseDec } from "./decimal"

// The limits an account's orders must stay inside, with the fields, titles and hints of the SwiftUI account
// editor (AccountEditorSheet.swift): position limits, timing, and behavior. The account's name, mode and keys
// are Connections', so they are not here.

type MoneyKey = "max_order_usd" | "max_symbol_usd" | "max_total_usd" | "daily_loss_cap_usd" | "max_above_signal_pct" | "max_below_signal_pct"
type CountKey = "max_entries_per_day" | "max_signal_age_seconds" | "order_timeout_seconds"
type FlagKey = "extended_hours" | "overnight" | "copy_exits" | "approve_orders"

export interface TextField {
  key: MoneyKey
  title: string
  hint: string
  /** A dollar amount or percent, kept as the decimal string the engine takes. */
  min: "positive" | "zero"
  /** What one press of a stepper adds. */
  step: number
}
export interface CountField {
  key: CountKey
  title: string
  hint: string
  step: number
}
export interface FlagField {
  key: FlagKey
  title: string
  hint: string
}

export const POSITION_LIMITS: TextField[] = [
  { key: "max_order_usd", title: "Largest single buy", hint: "The most one buy spends, and what a call with no size buys.", min: "positive", step: 10 },
  { key: "max_symbol_usd", title: "Maximum per stock", hint: "Shares CopyTrading bought. Your own aren't counted.", min: "positive", step: 10 },
  { key: "max_total_usd", title: "Maximum total exposure", hint: "Every stock CopyTrading bought. Your own aren't counted.", min: "positive", step: 10 },
  { key: "daily_loss_cap_usd", title: "Daily loss cap", hint: "Stops buying for the day. Still sells.", min: "positive", step: 10 },
  { key: "max_above_signal_pct", title: "Maximum above signal price (%)", hint: "0 means never more than the guru paid.", min: "zero", step: 0.5 },
  { key: "max_below_signal_pct", title: "Lowest sell price (% under the guru's)", hint: "A sell waits at this price or better until it fills.", min: "zero", step: 0.5 },
]

export const TIMING_LIMITS: CountField[] = [
  { key: "max_entries_per_day", title: "Entries per day", hint: "Sells don't count.", step: 1 },
  { key: "max_signal_age_seconds", title: "Maximum signal age (seconds)", hint: "Older buys aren't copied. A sell always is.", step: 5 },
  { key: "order_timeout_seconds", title: "Order timeout (seconds)", hint: "An unfilled buy is cancelled. A sell keeps waiting.", step: 5 },
]

export const BEHAVIORS: FlagField[] = [
  { key: "extended_hours", title: "Trade in extended hours", hint: "4:00 AM–9:30 AM and 4:00 PM–8:00 PM New York time, with limit orders." },
  { key: "overnight", title: "Trade overnight", hint: "8:00 PM–4:00 AM New York time. Needs extended hours." },
  { key: "copy_exits", title: "Copy exits", hint: "Off means you sell copied shares yourself." },
  { key: "approve_orders", title: "Ask me before sending orders", hint: "Each order waits for your approval." },
]

export const RECOVERY_HINT: Record<RecoveryPreference, string> = {
  automatic: "Buys again once its checks pass.",
  manual: "Buys wait for your Start Copying.",
}
export const RECOVERY_TITLE: Record<RecoveryPreference, string> = { manual: "Wait for me", automatic: "Carry on by itself" }

/** What the owner edits: every text field as typed, so a half-typed number is never rewritten under them. */
export type LimitsDraft = Record<MoneyKey | CountKey, string> & Record<FlagKey, boolean> & { recovery_preference: RecoveryPreference }

const MONEY_KEYS = POSITION_LIMITS.map((f) => f.key)
const COUNT_KEYS = TIMING_LIMITS.map((f) => f.key)
const FLAG_KEYS = BEHAVIORS.map((f) => f.key)

export function draftFromPolicy(policy: AccountPolicy): LimitsDraft {
  return {
    ...Object.fromEntries(MONEY_KEYS.map((k) => [k, policy[k]])),
    ...Object.fromEntries(COUNT_KEYS.map((k) => [k, String(policy[k])])),
    ...Object.fromEntries(FLAG_KEYS.map((k) => [k, policy[k]])),
    recovery_preference: policy.recovery_preference,
  } as LimitsDraft
}

/** Overnight runs only with extended hours, so turning those off ends it too and turning it on starts them. */
export function setFlag(draft: LimitsDraft, key: FlagKey, on: boolean): LimitsDraft {
  const next = { ...draft, [key]: on }
  if (key === "extended_hours" && !on) next.overnight = false
  if (key === "overnight" && on) next.extended_hours = true
  return next
}

/** One sentence per field that cannot be saved, by field. */
export function limitErrors(draft: LimitsDraft): Partial<Record<MoneyKey | CountKey, string>> {
  const errors: Partial<Record<MoneyKey | CountKey, string>> = {}
  for (const field of POSITION_LIMITS) {
    const value = parseDec(draft[field.key])
    if (value === null || value < 0n) errors[field.key] = "Enter a number, like 250."
    else if (field.min === "positive" && value === 0n) errors[field.key] = "Must be more than 0."
  }
  for (const field of TIMING_LIMITS) {
    if (!/^\d+$/.test(draft[field.key].trim()) || Number(draft[field.key]) < 1) errors[field.key] = "Enter a whole number, 1 or more."
  }
  return errors
}

/** The policy with the draft's limits in it; everything the draft does not edit (polling) is kept as saved. */
export function policyFromDraft(draft: LimitsDraft, saved: AccountPolicy): AccountPolicy {
  return {
    ...saved,
    ...Object.fromEntries(MONEY_KEYS.map((k) => [k, draft[k].trim()])),
    ...Object.fromEntries(COUNT_KEYS.map((k) => [k, Number(draft[k].trim())])),
    ...Object.fromEntries(FLAG_KEYS.map((k) => [k, draft[k]])),
    recovery_preference: draft.recovery_preference,
  }
}

/** The whole setup with one account's limits replaced: `updateAccountLimits` takes the whole configuration. */
export function withLimits(configuration: TradingConfiguration, accountId: string, policy: AccountPolicy): TradingConfiguration {
  return { ...configuration, accounts: configuration.accounts.map((a) => (a.id === accountId ? { ...a, policy } : a)) }
}

/** Whether saving would change anything: "100" and "100.0" are the same limit. */
export function limitsChanged(draft: LimitsDraft, saved: AccountPolicy): boolean {
  const next = policyFromDraft(draft, saved)
  return (Object.keys(next) as (keyof AccountPolicy)[]).some((key) => {
    const a = next[key]
    const b = saved[key]
    return typeof a === "string" && typeof b === "string" ? (parseDec(a) ?? a) !== (parseDec(b) ?? b) : a !== b
  })
}

/** A draft field as the number a stepper shows; null when it is empty or not a plain number. */
export const draftNumber = (text: string): number | null => (parseDec(text) === null ? null : Number(text))

/** A stepper's number back as the decimal the draft holds, rounded to six places so a step never leaves 0.30000000000000004; cleared is empty, which the field's own check then refuses. */
export const numberDraft = (value: number | null): string => (value === null || !Number.isFinite(value) ? "" : String(+value.toFixed(6)))
