import type { AccountOverview } from "../../../shared/contract"
import { dateTime } from "@/lib/format"
import { count } from "./words"

/** Every record whose name the saved setup doesn't use. */
export function earlierAccounts(accounts: AccountOverview[], saved: string[]): AccountOverview[] {
  const inSetup = new Set(saved)
  return accounts.filter((a) => !inSetup.has(a.account_id))
}

/** "Alpaca paper account ending 0f11 · 2 copied buys · Last active Oct 12, 2:15 PM". */
export function recordSummary(account: AccountOverview): string {
  const buys = account.positions.reduce((total, p) => total + p.lots.length, 0)
  const parts = [
    `Alpaca ${account.environment} account ending ${(account.broker_identity ?? "").slice(-4)}`,
    buys === 0 ? "No copied shares" : count(buys, "copied buy"),
  ]
  if (account.last_activity_at) parts.push(`Last active ${dateTime(account.last_activity_at)}`)
  return parts.join(" · ")
}
