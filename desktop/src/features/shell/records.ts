import type { AccountOverview, TradingConfiguration } from "../../../shared/contract"

/**
 * The accounts the saved setup copies, then the records left from earlier runs. Until the setup is read, or when none is
 * saved, nothing is called old: the owner sees every account rather than a list that hides one by mistake.
 */
export function splitRecords(accounts: AccountOverview[], setup: TradingConfiguration | null | undefined): { live: AccountOverview[]; old: AccountOverview[] } {
  if (!setup) return { live: accounts, old: [] }
  const inSetup = new Set(setup.accounts.map((a) => a.id))
  return { live: accounts.filter((a) => inSetup.has(a.account_id)), old: accounts.filter((a) => !inSetup.has(a.account_id)) }
}
